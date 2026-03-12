//
//  TabHibernationManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

// I feel like I could take the chrome approach
// Monitering tabs for memory ussage
// that might be better :think_emoji:
import Foundation

@MainActor
final class TabHibernationManager {
    private let maxLiveTabs: Int

    init(maxLiveTabs: Int = 10) {
        self.maxLiveTabs = maxLiveTabs
    }

    func hibernateInactiveTabs(tabs: [Tab], activeTabID: UUID?) {
        // logic is in resource manager
        // this is a fallback
        // maybe not a good one...
        let liveTabs = tabs.filter { !$0.isHibernated }
        guard liveTabs.count > maxLiveTabs else {
            return
        }

        let candidates = liveTabs
            .filter { $0.id != activeTabID }
            .sorted { $0.lastActivatedAt < $1.lastActivatedAt }

        let tabsToHibernate = max(0, liveTabs.count - maxLiveTabs)
        for tab in candidates.prefix(tabsToHibernate) {
            tab.hibernate()
            AppLog.info("Hibernated tab: \(tab.id.uuidString)")
        }
    }
}
