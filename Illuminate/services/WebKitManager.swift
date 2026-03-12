//
//  WebKitManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//


import Foundation
import WebKit
import Combine

@MainActor
final class WebKitManager: ObservableObject {

    static let shared = WebKitManager()

    @Published var cookiesEnabled: Bool = true

    private init() {
        URLCache.shared.memoryCapacity = 100 * 1024 * 1024 // Increase to 100MB
        URLCache.shared.diskCapacity = 500 * 1024 * 1024 // 500MB disk cache
    }

    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        
        configuration.mediaTypesRequiringUserActionForPlayback = []

        configuration.websiteDataStore = cookiesEnabled
            ? .default()
            : .nonPersistent()

        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let preferences = WKPreferences()
        preferences.isTextInteractionEnabled = true
        preferences.isElementFullscreenEnabled = true

        configuration.preferences = preferences
        configuration.userContentController = WKUserContentController()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        if let ruleList = AdBlockService.shared.contentRuleList {
            configuration.userContentController.add(ruleList)
        }

        return configuration
    }

    func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        applySafariUserAgent(to: webView)
        return webView
    }

    func applySafariUserAgent(to webView: WKWebView) {
        webView.evaluateJavaScript("navigator.userAgent") { result, _ in
            if let ua = result as? String {
                AppLog.info("Current UA: \(ua)")
                webView.customUserAgent = ua
            }
        }
    }
}
