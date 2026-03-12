//
//  TabManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

import Combine
import Foundation
import SwiftUI
import WebKit

struct ClosedTabSnapshot {
    let payload: TabTransferPayload
}

@MainActor
final class TabManager: ObservableObject {

    static let shared = TabManager()
    static let sharedPlaceholder = TabManager(isPersistenceEnabled: false)

    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var activeTabID: UUID?
    @Published private(set) var tabGroups: [TabGroup] = []
    @Published var hoveredSidebarTabID: UUID?

    @Published var windowThemeColor: Color {
        didSet {
            guard isPersistenceEnabled else { return }
            userDefaults.set(windowThemeColor.toHex(), forKey: "windowThemeColor")
        }
    }

    @Published var backgroundImagePalette: [Color] = []

    @Published var backgroundImageURL: String {
        didSet {
            guard isPersistenceEnabled else { return }
            userDefaults.set(backgroundImageURL, forKey: "backgroundImageURL")
            if !isInitializing {
                updateThemeFromBackground(setTheme: true)
            }
        }
    }

    @Published var showSidebar: Bool {
        didSet {
            guard isPersistenceEnabled else { return }
            userDefaults.set(showSidebar, forKey: "showSidebar")
        }
    }

    @Published var showBackgroundBehindSidebar: Bool {
        didSet {
            guard isPersistenceEnabled else { return }
            userDefaults.set(showBackgroundBehindSidebar, forKey: "showBackgroundBehindSidebar")
        }
    }

    @Published var isResizing: Bool = false
    @Published var isFullScreen: Bool = false

    @Published var userInterfaceStyle: UIStyle {
        didSet {
            guard isPersistenceEnabled else { return }
            userDefaults.set(userInterfaceStyle.rawValue, forKey: "userInterfaceStyle")
        }
    }

    enum UIStyle: String, CaseIterable {
        case dark
        case light
        case system

        var colorScheme: ColorScheme? {
            switch self {
            case .dark: return .dark
            case .light: return .light
            case .system: return nil
            }
        }
    }

    var activeTab: Tab? {
        guard let activeTabID else { return nil }
        return tabs.first { $0.id == activeTabID }
    }

    private let notificationCenter: NotificationCenter
    private let hibernationManager: TabHibernationManager
    private let urlSynchronizer: URLSynchronizer
    private let userDefaults: UserDefaults
    private let isPersistenceEnabled: Bool

    private var recentlyClosed: [ClosedTabSnapshot] = []
    private var isInitializing = true

    @MainActor
    init(
        notificationCenter: NotificationCenter = .default,
        hibernationManager: TabHibernationManager? = nil,
        urlSynchronizer: URLSynchronizer? = nil,
        userDefaults: UserDefaults = .standard,
        isPersistenceEnabled: Bool = true
    ) {
        self.notificationCenter = notificationCenter
        self.hibernationManager = hibernationManager ?? TabHibernationManager()
        self.urlSynchronizer = urlSynchronizer ?? URLSynchronizer.shared
        self.userDefaults = userDefaults
        self.isPersistenceEnabled = isPersistenceEnabled

        let savedHex = isPersistenceEnabled ? (userDefaults.string(forKey: "windowThemeColor") ?? "89BBFF") : "89BBFF"
        self.windowThemeColor = Color(hex: savedHex)

        self.backgroundImageURL = isPersistenceEnabled ? (userDefaults.string(forKey: "backgroundImageURL") ?? "") : ""
        self.showSidebar = isPersistenceEnabled ? (userDefaults.object(forKey: "showSidebar") as? Bool ?? true) : true
        self.showBackgroundBehindSidebar = isPersistenceEnabled ? (userDefaults.object(forKey: "showBackgroundBehindSidebar") as? Bool ?? true) : true

        let savedStyle = isPersistenceEnabled ? (userDefaults.string(forKey: "userInterfaceStyle") ?? "dark") : "dark"
        self.userInterfaceStyle = UIStyle(rawValue: savedStyle) ?? .dark

        if isPersistenceEnabled {
            if let savedGroupsData = userDefaults.data(forKey: "savedTabGroups"),
               let savedGroups = try? JSONDecoder().decode([TabGroup].self, from: savedGroupsData) {
                tabGroups = savedGroups
            }

            if let savedTabsData = userDefaults.data(forKey: "savedTabs"),
               let savedPayloads = try? JSONDecoder().decode([TabTransferPayload].self, from: savedTabsData) {
                tabs = savedPayloads.map { payload in
                    let tab = Tab(payload: payload)
                    tab.onMetadataUpdate = { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.saveState()
                        }
                    }
                    return tab
                }
            }

            if let savedActiveTabIDString = userDefaults.string(forKey: "savedActiveTabID"),
               let savedActiveTabID = UUID(uuidString: savedActiveTabIDString) {
                activeTabID = savedActiveTabID
            }
        }

        setupObservers()

        if tabs.isEmpty {
            createTab()
        }

        Task { @MainActor [weak self] in
            self?.isInitializing = false
            self?.updateThemeFromBackground(setTheme: false)
        }
    }

    func clearAllTabs() {
        tabs.removeAll()
        activeTabID = nil
        saveState()
    }

    private func setupObservers() {
        notificationCenter.addObserver(forName: .newTab, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.createTab() }
        }

        notificationCenter.addObserver(forName: .reloadActiveTab, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activeTab?.reload() }
        }

        notificationCenter.addObserver(forName: .goBack, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activeTab?.webView?.goBack() }
        }

        notificationCenter.addObserver(forName: .goForward, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activeTab?.webView?.goForward() }
        }

        notificationCenter.addObserver(forName: .reopenTab, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reopenLastClosedTab() }
        }

        notificationCenter.addObserver(forName: .nextTab, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.nextTab() }
        }

        notificationCenter.addObserver(forName: .previousTab, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.previousTab() }
        }

        notificationCenter.addObserver(forName: NSNotification.Name("closeActiveTab"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.closeActiveTab() }
        }

        notificationCenter.addObserver(forName: .toggleSidebar, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self?.showSidebar.toggle()
                }
            }
        }

        notificationCenter.addObserver(forName: .openDevTools, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeTab?.openDevTools()
            }
        }

        notificationCenter.addObserver(forName: .zoomIn, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeTab?.zoomIn()
            }
        }

        notificationCenter.addObserver(forName: .zoomOut, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeTab?.zoomOut()
            }
        }

        notificationCenter.addObserver(forName: .resetZoom, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeTab?.resetZoom()
            }
        }
    }

    private func updateThemeFromBackground(setTheme: Bool) {
        guard let url = URL(string: backgroundImageURL), !backgroundImageURL.isEmpty else {
            backgroundImagePalette = []
            return
        }

        Task {
            let palette = await ImageColorExtractor.shared.extractPalette(from: url)

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.8)) {
                    backgroundImagePalette = palette
                    if setTheme, let first = palette.first {
                        windowThemeColor = first
                    }
                }
            }
        }
    }

    private func saveState() {
        guard isPersistenceEnabled else { return }

        if let encodedGroups = try? JSONEncoder().encode(tabGroups) {
            userDefaults.set(encodedGroups, forKey: "savedTabGroups")
        }

        let payloads = tabs.map { $0.toTransferPayload() }

        if let encodedTabs = try? JSONEncoder().encode(payloads) {
            userDefaults.set(encodedTabs, forKey: "savedTabs")
        }

        if let activeTabID {
            userDefaults.set(activeTabID.uuidString, forKey: "savedActiveTabID")
        }
    }

    @discardableResult
    func createTab(url: URL? = nil) -> Tab {
        let tab = Tab(url: url)
        tab.onMetadataUpdate = { [weak self] in
            Task { @MainActor [weak self] in
                self?.saveState()
            }
        }
        tabs.append(tab)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switchTo(tab.id)
        }
        applyHibernationPolicy()
        saveState()

        if url == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .focusNewTabSearchBar, object: nil)
            }
        }

        return tab
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = tabs[index]
        recentlyClosed.append(ClosedTabSnapshot(payload: tab.toTransferPayload()))

        tabs.remove(at: index)
        
        // Clean up assets for this tab
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths[0].appendingPathComponent("Illuminate/TabAssets", isDirectory: true)
        let tabFolder = base.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: tabFolder)

        if activeTabID == id {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if let lastID = tabs.last?.id {
                    switchTo(lastID)
                } else {
                    activeTabID = nil
                    syncActiveTabURL()
                }
            }
        }

        saveState()
    }

    func closeActiveTab() {
        guard let activeTabID else { return }
        closeTab(id: activeTabID)
    }

    @discardableResult
    func reopenLastClosedTab() -> Tab? {
        guard let snapshot = recentlyClosed.popLast() else { return nil }

        let tab = Tab(payload: snapshot.payload)
        tab.onMetadataUpdate = { [weak self] in
            Task { @MainActor [weak self] in
                self?.saveState()
            }
        }
        tabs.append(tab)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switchTo(tab.id)
        }
        saveState()

        return tab
    }

    func moveTab(fromOffsets: IndexSet, toOffset: Int) {
        tabs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveState()
    }

    func nextTab() {
        guard let currentID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == currentID }) else { return }

        let nextIndex = (index + 1) % tabs.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            switchTo(tabs[nextIndex].id)
        }
    }

    func previousTab() {
        guard let currentID = activeTabID,
              let index = tabs.firstIndex(where: { $0.id == currentID }) else { return }

        let prevIndex = (index - 1 + tabs.count) % tabs.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            switchTo(tabs[prevIndex].id)
        }
    }

    func switchTo(_ id: UUID) {
        if activeTabID == id { return }

        setActiveTab(id)
        applySuspensionPolicy()
    }

    private func applySuspensionPolicy() {
        let liveTabs = tabs.filter { $0.webView != nil && $0.id != activeTabID }

        let limit: Int
        if tabs.count > 25 {
            limit = 5
        } else if tabs.count > 10 {
            limit = 8
        } else {
            // Keep all tabs loaded if less than 10
            return
        }

        if liveTabs.count > limit {
            let sorted = liveTabs.sorted { $0.lastAccessed < $1.lastAccessed }
            let toSuspend = liveTabs.count - limit

            for i in 0..<toSuspend {
                if tabs.count > 25 {
                    sorted[i].suspend()
                } else {
                    sorted[i].freeze()
                }
            }
        }
    }

    func setActiveTab(_ id: UUID?) {
        activeTabID = id

        if let tab = tabs.first(where: { $0.id == id }) {
            tab.markActivated()
            tab.markAccessed()
            tab.thaw()
        }

        syncActiveTabURL()
        applyHibernationPolicy()
        applySuspensionPolicy()
        saveState()
    }

    func updateTabURL(tabID: UUID, url: URL?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }

        DispatchQueue.main.async {
            tab.url = url
        }

        if tabID == activeTabID {
            syncActiveTabURL()
        }

        saveState()
    }

    func createTabGroup(name: String, color: String) {
        tabGroups.append(TabGroup(name: name, color: color))
        saveState()
    }

    func removeTabGroup(id: UUID) {
        tabGroups.removeAll { $0.id == id }

        for tab in tabs where tab.groupID == id {
            tab.groupID = nil
        }

        saveState()
    }

    func toggleGroupExpansion(id: UUID) {
        if let index = tabGroups.firstIndex(where: { $0.id == id }) {
            tabGroups[index].isExpanded.toggle()
        }

        saveState()
    }

    func setTabGroup(tabID: UUID, groupID: UUID?) {
        tabs.first { $0.id == tabID }?.groupID = groupID
        saveState()
    }

    private func syncActiveTabURL() {
        urlSynchronizer.updateCurrentURL(activeTab?.url)
    }

    private func applyHibernationPolicy() {
        guard tabs.count > 50 else { return }
        hibernationManager.hibernateInactiveTabs(tabs: tabs, activeTabID: activeTabID)
    }
}
