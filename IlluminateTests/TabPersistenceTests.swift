//
//  TabPersistenceTests.swift
//  IlluminateTests
//
//  Created by MrBlankCoding on 3/9/26.
//

import Testing
import Foundation
import AppKit
@testable import Illuminate

struct TabPersistenceTests {

    private func createTestUserDefaults() -> UserDefaults {
        let suiteName = "TabPersistenceTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @MainActor
    @Test func testSessionSerialization() async throws {
        let userDefaults = createTestUserDefaults()
        let tabManager = TabManager(userDefaults: userDefaults)
        
        // 1 empty
        let initialCount = tabManager.tabs.count
        #expect(initialCount == 1)
        
        let tab1 = tabManager.createTab(url: URL(string: "https://apple.com"))
        tab1.title = "Apple"
        let tab2 = tabManager.createTab(url: URL(string: "https://google.com"))
        tab2.title = "Google"
        
        // make sure it has data
        let savedTabsData = userDefaults.data(forKey: "savedTabs")
        #expect(savedTabsData != nil)
        
        let savedActiveTabIDString = userDefaults.string(forKey: "savedActiveTabID")
        let tab2ID = tab2.id
        #expect(savedActiveTabIDString == tab2ID.uuidString)
        
        let newTabManager = TabManager(userDefaults: userDefaults)
        
        // should have 3
        let newCount = newTabManager.tabs.count
        #expect(newCount == 3)
        
        let hasApple = newTabManager.tabs.contains { $0.url?.absoluteString == "https://apple.com" && $0.title == "Apple" }
        let hasGoogle = newTabManager.tabs.contains { $0.url?.absoluteString == "https://google.com" && $0.title == "Google" }
        let activeID = newTabManager.activeTabID
        let tab2IDCheck = tab2.id
        
        #expect(hasApple == true)
        #expect(hasGoogle == true)
        #expect(activeID == tab2IDCheck)
    }

    @MainActor
    @Test func testCrashRecovery() async throws {
        let userDefaults = createTestUserDefaults()
        let tabId1 = UUID()
        let tabId2 = UUID()
        let payload1 = TabTransferPayload(id: tabId1, url: URL(string: "https://github.com"), title: "GitHub", isHibernated: false, state: nil, groupID: nil)
        let payload2 = TabTransferPayload(id: tabId2, url: URL(string: "https://swift.org"), title: "Swift", isHibernated: true, state: nil, groupID: nil)
        
        let encodedTabs = try JSONEncoder().encode([payload1, payload2])
        userDefaults.set(encodedTabs, forKey: "savedTabs")
        userDefaults.set(tabId1.uuidString, forKey: "savedActiveTabID")
        
        let tabManager = TabManager(userDefaults: userDefaults)
        let tabCount = tabManager.tabs.count
        let hasGitHub = tabManager.tabs.contains { $0.id == tabId1 && $0.title == "GitHub" }
        let hasSwift = tabManager.tabs.contains { $0.id == tabId2 && $0.title == "Swift" && $0.isHibernated == true }
        let activeID = tabManager.activeTabID
        
        #expect(tabCount == 2)
        #expect(hasGitHub == true)
        #expect(hasSwift == true)
        #expect(activeID == tabId1)
    }

    @MainActor
    @Test func testTabClosingCleanup() async throws {
        let userDefaults = createTestUserDefaults()
        let tabManager = TabManager(userDefaults: userDefaults)
        
        let tab = tabManager.createTab(url: URL(string: "https://apple.com"))
        let tabID = tab.id
        
        #expect(userDefaults.data(forKey: "savedTabs") != nil)
        
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths[0].appendingPathComponent("Illuminate/TabAssets", isDirectory: true)
        let tabFolder = base.appendingPathComponent(tabID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tabFolder, withIntermediateDirectories: true)
        let dummyAsset = tabFolder.appendingPathComponent("snapshot.png")
        try "dummy".data(using: .utf8)?.write(to: dummyAsset)
        
        #expect(FileManager.default.fileExists(atPath: tabFolder.path))
        
        tabManager.closeTab(id: tabID)
        
        let savedTabsData = userDefaults.data(forKey: "savedTabs")!
        let savedPayloads = try JSONDecoder().decode([TabTransferPayload].self, from: savedTabsData)
        #expect(!savedPayloads.contains { $0.id == tabID })
        
        #expect(!FileManager.default.fileExists(atPath: tabFolder.path), "Tab folder should be deleted from disk")
    }
}
