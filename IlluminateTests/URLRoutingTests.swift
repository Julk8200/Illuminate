//
//  URLRoutingTests.swift
//  IlluminateTests
//
//  Created by MrBlankCoding on 3/9/26.
//

import Testing
import Foundation
import WebKit
@testable import Illuminate

struct URLRoutingTests {

    @Test func testSearchQueryRouting() async throws {
        let tabManager = await MainActor.run { TabManager(isPersistenceEnabled: false) }
        let viewModel = await MainActor.run { ContentViewModel(tabManager: tabManager) }
        let tab = await MainActor.run {
            let t = tabManager.createTab()
            tabManager.switchTo(t.id)
            return t
        }
        
        await MainActor.run {
            viewModel.addressBarText = "hello world"
            viewModel.navigateToAddressBarURL()
        }
        
        let tabHost = await MainActor.run { tab.url?.host }
        let tabQuery = await MainActor.run { tab.url?.query }
        
        #expect(tabHost == "www.google.com")
        #expect(tabQuery?.contains("q=hello%20world") == true)
    }

    @Test func testAutoHTTPSRouting() async throws {
        let tabManager = await MainActor.run { TabManager(isPersistenceEnabled: false) }
        let viewModel = await MainActor.run { ContentViewModel(tabManager: tabManager) }
        let tab = await MainActor.run {
            let t = tabManager.createTab()
            tabManager.switchTo(t.id)
            return t
        }
        
        await MainActor.run {
            viewModel.addressBarText = "apple.com"
            viewModel.navigateToAddressBarURL()
        }
        
        let tabURL = await MainActor.run { tab.url?.absoluteString }
        
        #expect(tabURL == "https://apple.com")
    }
}
