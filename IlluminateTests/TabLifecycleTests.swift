//
//  TabLifecycleTests.swift
//  IlluminateTests
//
//  Created by MrBlankCoding on 3/9/26.
//

import Testing
import WebKit
import Foundation
@testable import Illuminate

struct TabLifecycleTests {

    @Test func testLazyWebViewCreation() async throws {
        await MainActor.run {
            let tab = Tab(url: URL(string: "https://apple.com"), title: "Apple")
            
            #expect(tab.webView == nil, "WebView should be nil initially (lazy loading)")
            
            let config = WKWebViewConfiguration()
            tab.createWebViewIfNeeded(configuration: config)
            let strongWebView = tab.webView
            
            #expect(tab.webView != nil, "WebView should be created after calling createWebViewIfNeeded")
            _ = strongWebView 
        }
    }
    
    @Test func testTabSuspension() async throws {
        await MainActor.run {
            let tab = Tab(url: URL(string: "https://apple.com"), title: "Apple")
            tab.createWebViewIfNeeded(configuration: WKWebViewConfiguration())
            
            #expect(tab.webView != nil)
            #expect(tab.isHibernated == false)
            tab.detachWebView()
            tab.suspend()
            
            #expect(tab.isHibernated == true, "Tab should be marked as hibernated immediately")
            #expect(tab.webView == nil, "WebView should be released immediately")
            #expect(tab.discardTier == .medium, "Suspended tabs should use the medium discard tier")
        }
    }

    @MainActor
    @Test func testTabRestoration() async throws {
        let tab = Tab(url: URL(string: "https://apple.com"), title: "Apple")
        
        tab.isHibernated = true
        tab.detachWebView()
        
        #expect(tab.isHibernated)
        #expect(tab.webView == nil)
        
        let config = WKWebViewConfiguration()
        tab.createWebViewIfNeeded(configuration: config)
        let strongWebView = tab.webView

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(strongWebView != nil, "WebView should be strongly retained during restoration")
        #expect(tab.webView != nil, "WebView should be recreated on restoration")
        #expect(tab.isHibernated == false, "Tab should no longer be hibernated")
        #expect(tab.discardTier == .active, "Restored tabs should return to the active tier")
    }

    @Test func testTabDiscardTierProgression() async throws {
        await MainActor.run {
            let tab = Tab(url: URL(string: "https://apple.com"), title: "Apple")
            tab.createWebViewIfNeeded(configuration: WKWebViewConfiguration())

            tab.freeze()
            #expect(tab.discardTier == .light)

            tab.applyDiscardTier(.medium)
            #expect(tab.discardTier == .medium)
            #expect(tab.isHibernated)

            tab.hibernate()
            #expect(tab.discardTier == .full)
        }
    }

    @Test func testWebViewWithoutProcessIdentifierDoesNotCrash() async throws {
        await MainActor.run {
            class FakeWebView: WKWebView {
                override func responds(to aSelector: Selector!) -> Bool {
                    if NSStringFromSelector(aSelector) == "processIdentifier" {
                        return false
                    }
                    return super.responds(to: aSelector)
                }
            }

            let tab = Tab(url: URL(string: "https://apple.com"), title: "Test")
            let fake = FakeWebView(frame: .zero, configuration: WKWebViewConfiguration())
            try! tab.attachWebView(fake) // this exercises setupWebViewObservers
            #expect(tab.processIdentifier == 0, "Process ID should remain 0 when not available")
            #expect(tab.webView === fake, "Fake webview should be attached")
        }
    }
}
