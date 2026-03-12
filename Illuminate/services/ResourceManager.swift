//
//  ResourceManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/9/26.
//

import Foundation
import WebKit
import Combine
import Darwin

// Define the required Mach/BSD constants and structures for proc_pidinfo
private let PROC_PIDTASKINFO: Int32 = 4

struct proc_taskinfo {
    var pti_virtual_size: UInt64
    var pti_resident_size: UInt64
    var pti_total_user: UInt64
    var pti_total_system: UInt64
    var pti_threads_user: UInt64
    var pti_threads_system: UInt64
    var pti_policy: Int32
    var pti_faults: Int32
    var pti_pageins: Int32
    var pti_cow_faults: Int32
    var pti_messages_sent: Int32
    var pti_messages_received: Int32
    var pti_syscalls_mach: Int32
    var pti_syscalls_unix: Int32
    var pti_csw: Int32
    var pti_threadnum: Int32
    var pti_numrunning: Int32
    var pti_priority: Int32
}

@_silgen_name("proc_pidinfo")
func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@MainActor
final class ResourceManager: ObservableObject {
    static let shared = ResourceManager()
    
    @Published var autoHibernateEnabled: Bool = true
    @Published var memoryThresholdMB: UInt64 = 300 
    @Published var checkInterval: TimeInterval = 5 
    
    private let tabManager: TabManager
    private let memoryProvider: (Int32) -> UInt64
    
    func resetForTesting() {
        lastCheckTimes.removeAll()
    }
    
    private var timer: Timer?
    private var lastCheckTimes: [UUID: Date] = [:]
    private let backgroundCheckInterval: TimeInterval = 60 
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    
    init(tabManager: TabManager? = nil, memoryProvider: ((Int32) -> UInt64)? = nil) {
        self.tabManager = tabManager ?? TabManager.shared
        self.memoryProvider = memoryProvider ?? { pid in
            var taskInfo = proc_taskinfo(
                pti_virtual_size: 0, pti_resident_size: 0, pti_total_user: 0, pti_total_system: 0,
                pti_threads_user: 0, pti_threads_system: 0, pti_policy: 0, pti_faults: 0,
                pti_pageins: 0, pti_cow_faults: 0, pti_messages_sent: 0, pti_messages_received: 0,
                pti_syscalls_mach: 0, pti_syscalls_unix: 0, pti_csw: 0, pti_threadnum: 0,
                pti_numrunning: 0, pti_priority: 0
            )
            
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
            
            if result == size {
                return taskInfo.pti_resident_size
            }
            return 0
        }
        
        startMonitoring()
        DispatchQueue.main.async { [weak self] in
            self?.performMemoryCheck()
        }
        setupMemoryPressureMonitoring()
    }
    
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performMemoryCheck()
            }
        }
    }
    
    func performMemoryCheck() {
        let tabs = tabManager.tabs
        let activeTabID = tabManager.activeTabID
        let now = Date()
        
        for tab in tabs {
            guard tab.webView != nil, !tab.isHibernated else { 
                if tab.isHibernated {
                    updateTabMemory(tab, bytes: 0)
                }
                continue 
            }
            
            // Determine if we should check this tab based on whether it's active or background
            let isActive = tab.id == activeTabID
            let lastCheck = lastCheckTimes[tab.id] ?? .distantPast
            let elapsed = now.timeIntervalSince(lastCheck)
            
            if !isActive && elapsed < backgroundCheckInterval {
                continue
            }
            
            lastCheckTimes[tab.id] = now
            
            if tab.processIdentifier != 0 {
                let bytes = memoryProvider(tab.processIdentifier)
                updateTabMemory(tab, bytes: bytes)
            } else {
                updateTabMemory(tab, bytes: 0)
            }
        }
    }
    
    private func updateTabMemory(_ tab: Tab, bytes: UInt64) {
        DispatchQueue.main.async {
            tab.memoryUsage = bytes
            
            guard self.autoHibernateEnabled,
                  tab.id != self.tabManager.activeTabID
            else {
                return
            }
            
            let heavyBytes = self.memoryThresholdMB * 1024 * 1024
            let freezeBytes = UInt64(Double(heavyBytes) * 0.6)
            let recentlyActivated = Date().timeIntervalSince(tab.lastActivatedAt) < 60
            let totalTabs = self.tabManager.tabs.count
            let allowHibernate = totalTabs > 5
            
            if bytes > heavyBytes && !recentlyActivated && allowHibernate {
                AppLog.info("Hibernating background tab \(tab.title) (\(bytes / 1024 / 1024)MB)")
                tab.hibernate()
            } else if bytes > freezeBytes && !recentlyActivated && !tab.isFrozen && !tab.isHibernated {
                AppLog.info("Freezing background tab \(tab.title) (\(bytes / 1024 / 1024)MB)")
                tab.freeze()
            }
        }
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        
        source.setEventHandler { [weak self, weak source] in
            guard let self = self, let source = source else { return }
            let event = source.data
            self.handleMemoryPressure(event: event)
        }
        
        memoryPressureSource?.cancel()
        memoryPressureSource = source
        source.activate()
    }

    private func handleMemoryPressure(event: DispatchSource.MemoryPressureEvent) {
        let tabs = tabManager.tabs
        let activeTabID = tabManager.activeTabID
        let candidates = tabs.filter { $0.id != activeTabID && !$0.isHibernated }
        guard !candidates.isEmpty else { return }
        
        let sorted = candidates.sorted { $0.lastAccessed < $1.lastAccessed }
        
        let toSuspendCount: Int
        switch event {
        case .warning:
            toSuspendCount = max(1, sorted.count / 3)
        case .critical:
            toSuspendCount = sorted.count
        default:
            toSuspendCount = 0
        }
        
        guard toSuspendCount > 0 else { return }
        
        AppLog.info("Memory pressure \(event.rawValue); discarding \(toSuspendCount) background tab(s)")
        
        for tab in sorted.prefix(toSuspendCount) {
            tab.suspend()
        }
    }
}

