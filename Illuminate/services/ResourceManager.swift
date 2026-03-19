//
//  ResourceManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/9/26.
//

import Combine
import Darwin
import Foundation
import WebKit

private let PROC_PIDTASKINFO: Int32 = 4

// Mirror of the Darwin proc_taskinfo struct. Field names match the kernel struct
// exactly so this can be passed directly to proc_pidinfo without translation.
private struct proc_taskinfo {
    var pti_virtual_size:       UInt64 = 0
    var pti_resident_size:      UInt64 = 0
    var pti_total_user:         UInt64 = 0
    var pti_total_system:       UInt64 = 0
    var pti_threads_user:       UInt64 = 0
    var pti_threads_system:     UInt64 = 0
    var pti_policy:             Int32  = 0
    var pti_faults:             Int32  = 0
    var pti_pageins:            Int32  = 0
    var pti_cow_faults:         Int32  = 0
    var pti_messages_sent:      Int32  = 0
    var pti_messages_received:  Int32  = 0
    var pti_syscalls_mach:      Int32  = 0
    var pti_syscalls_unix:      Int32  = 0
    var pti_csw:                Int32  = 0
    var pti_threadnum:          Int32  = 0
    var pti_numrunning:         Int32  = 0
    var pti_priority:           Int32  = 0
}

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(
    _ pid: Int32,
    _ flavor: Int32,
    _ arg: UInt64,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int32
) -> Int32

@MainActor
final class ResourceManager: ObservableObject {
    private enum Policy {
        static let minTabsForHibernation = 5
        static let recentActivationWindow: TimeInterval = 60
        static let lightInactivityWindow: TimeInterval = 90
        static let mediumInactivityWindow: TimeInterval = 300
        static let fullInactivityWindow: TimeInterval = 900
        static let backgroundSampleInterval: TimeInterval = 60
        static let lightThresholdRatio: Double = 0.45
        static let mediumThresholdRatio: Double = 0.75
    }

    static let shared = ResourceManager()

    @Published var autoHibernateEnabled: Bool = true
    @Published var memoryThresholdMB: UInt64 = 300
    @Published var checkInterval: TimeInterval = 5 {
        didSet { restartTimer() }
    }

    private let tabManager: TabManager
    private let memoryProvider: (Int32) -> UInt64

    private var timer: Timer?
    private var lastCheckTimes: [UUID: Date] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(tabManager: TabManager? = nil, memoryProvider: ((Int32) -> UInt64)? = nil) {
        self.tabManager = tabManager ?? TabManager.shared
        self.memoryProvider = memoryProvider ?? Self.defaultMemoryProvider
        startMonitoring()
        performMemoryCheck()
        setupMemoryPressureMonitoring()
    }

    private static let defaultMemoryProvider: (Int32) -> UInt64 = { pid in
        guard pid != 0 else { return 0 }
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        return result == size ? info.pti_resident_size : 0
    }

    func startMonitoring() {
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.performMemoryCheck() }
        }
    }

    private struct TabCheckSpec {
        let id: UUID
        let pid: Int32
        let title: String
        let lastActivatedAt: Date
        let lastAccessed: Date
        let isFrozen: Bool
        let isActive: Bool
    }

    func performMemoryCheck() {
        let tabs = tabManager.tabs
        let activeTabID = tabManager.activeTabID
        let now = Date()
        let hibernatedTabIDs = tabs.compactMap { tab -> UUID? in
            guard tab.isHibernated, tab.memoryUsage != 0 else { return nil }
            return tab.id
        }
        let specs: [TabCheckSpec] = tabs.compactMap { tab in
            if tab.isHibernated {
                return nil
            }
            guard tab.webView != nil else { return nil }

            let isActive = tab.id == activeTabID
            let elapsed = now.timeIntervalSince(lastCheckTimes[tab.id] ?? .distantPast)
            guard isActive || elapsed >= Policy.backgroundSampleInterval else { return nil }

            return TabCheckSpec(
                id: tab.id,
                pid: tab.processIdentifier,
                title: tab.title,
                lastActivatedAt: tab.lastActivatedAt,
                lastAccessed: tab.lastAccessed,
                isFrozen: tab.isFrozen,
                isActive: isActive
            )
        }

        if !hibernatedTabIDs.isEmpty {
            Task { @MainActor [weak self] in
                self?.resetMemoryUsage(for: hibernatedTabIDs)
            }
        }

        guard !specs.isEmpty else { return }

        let provider = memoryProvider

        Task.detached(priority: .utility) { [weak self] in
            let samples: [(id: UUID, bytes: UInt64)] = specs.map { spec in
                (id: spec.id, bytes: provider(spec.pid))
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(samples: samples, specs: specs, sampledAt: now)
            }
        }
    }

    private func apply(samples: [(id: UUID, bytes: UInt64)], specs: [TabCheckSpec], sampledAt: Date) {
        let activeTabID = tabManager.activeTabID
        let totalTabs = tabManager.tabs.count
        let fullBytes = memoryThresholdMB * 1024 * 1024
        let mediumBytes = UInt64(Double(fullBytes) * Policy.mediumThresholdRatio)
        let lightBytes = UInt64(Double(fullBytes) * Policy.lightThresholdRatio)

        for (id, bytes) in samples {
            lastCheckTimes[id] = sampledAt

            guard let tab = tabManager.tabs.first(where: { $0.id == id }) else { continue }
            guard let spec = specs.first(where: { $0.id == id }) else { continue }
            tab.memoryUsage = bytes

            guard
                autoHibernateEnabled,
                id != activeTabID,
                totalTabs > Policy.minTabsForHibernation,
                !tab.recentlyActivated(within: Policy.recentActivationWindow)
            else { continue }

            let inactivity = sampledAt.timeIntervalSince(spec.lastAccessed)
            let targetTier: TabDiscardTier?

            if bytes > fullBytes && inactivity >= Policy.fullInactivityWindow {
                targetTier = .full
            } else if bytes > mediumBytes && inactivity >= Policy.mediumInactivityWindow {
                targetTier = .medium
            } else if bytes > lightBytes && inactivity >= Policy.lightInactivityWindow {
                targetTier = .light
            } else {
                targetTier = nil
            }

            guard let targetTier, targetTier.rawValue > tab.discardTier.rawValue else { continue }
            AppLog.info("Discarding '\(tab.title)' at \(targetTier) tier (\(bytes.toMB)MB)")
            tab.applyDiscardTier(targetTier)
        }
    }

    private func resetMemoryUsage(for ids: [UUID]) {
        guard !ids.isEmpty else { return }

        for id in ids {
            guard let tab = tabManager.tabs.first(where: { $0.id == id }) else { continue }
            tab.memoryUsage = 0
        }
    }

    private func applyPressureDiscardTier(_ tier: TabDiscardTier, to tabs: ArraySlice<Tab>) {
        for tab in tabs {
            guard tier.rawValue > tab.discardTier.rawValue else { continue }
            AppLog.info("Memory pressure escalated '\(tab.title)' to \(tier) tier")
            tab.applyDiscardTier(tier)
        }
    }

    private func setupMemoryPressureMonitoring() {
        memoryPressureSource?.cancel()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            self.handleMemoryPressure(event: event)
        }
        memoryPressureSource = source
        source.activate()
    }

    private func handleMemoryPressure(event: DispatchSource.MemoryPressureEvent) {
        let candidates = tabManager.tabs.filter {
            $0.id != tabManager.activeTabID && !$0.isHibernated
        }
        .sorted { $0.lastAccessed < $1.lastAccessed }

        guard !candidates.isEmpty else { return }

        switch event {
        case .warning:
            let count = max(1, candidates.count / 3)
            applyPressureDiscardTier(.medium, to: candidates.prefix(count))
        case .critical:
            applyPressureDiscardTier(.full, to: candidates[...])
        default: return
        }
    }

    func resetForTesting() {
        lastCheckTimes.removeAll()
    }

    /// Call this when tabs are closed to avoid unbounded growth.
    func pruneClosedTabs() {
        let liveIDs = Set(tabManager.tabs.map(\.id))
        lastCheckTimes = lastCheckTimes.filter { liveIDs.contains($0.key) }
    }
}

private extension Tab {
    func recentlyActivated(within window: TimeInterval) -> Bool {
        Date().timeIntervalSince(lastActivatedAt) < window
    }
}

private extension UInt64 {
    var toMB: UInt64 { self / 1024 / 1024 }
}

private extension DispatchSource.MemoryPressureEvent {
    var label: String {
        switch self {
        case .normal:   return "normal"
        case .warning:  return "warning"
        case .critical: return "critical"
        default:        return "unknown(\(rawValue))"
        }
    }
}
