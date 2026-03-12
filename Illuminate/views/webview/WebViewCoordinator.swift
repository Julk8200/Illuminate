//
//  WebViewCoordinator.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

import AppKit
import WebKit
import SwiftUI

extension WebViewRepresentable {
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
        private weak var tab: Tab?
        private let tabManager: TabManager
        private let webScriptBridge: WebScriptBridge
        private let adBlockService: AdBlockService
        private let dohService: DNSOverHTTPSService
        private let safeBrowsing: SafeBrowsingManager
        private let faviconCache: FaviconCache
        private weak var contextMenuWebView: WKWebView?
        private let circuitBreaker = WebProcessCircuitBreaker()
        private var isRestoringHibernatedState = false
        private var lastAppliedStyle: TabManager.UIStyle?
        private var lastAppliedContentRuleList: WKContentRuleList?
        var lastLoadedURL: URL?

        init(
            tab: Tab,
            tabManager: TabManager,
            webScriptBridge: WebScriptBridge,
            adBlockService: AdBlockService,
            dohService: DNSOverHTTPSService,
            safeBrowsing: SafeBrowsingManager,
            faviconCache: FaviconCache
        ) {
            self.tab = tab
            self.tabManager = tabManager
            self.webScriptBridge = webScriptBridge
            self.adBlockService = adBlockService
            self.dohService = dohService
            self.safeBrowsing = safeBrowsing
            self.faviconCache = faviconCache
            self.lastLoadedURL = tab.url
        }

        func restoreHibernatedState(into webView: WKWebView) {
            guard let tab = tab, tab.isHibernated, let state = tab.hibernatedState else { return }
            
            if let restoredURL = state.currentURL {
                var request = URLRequest(url: restoredURL)
                request.timeoutInterval = 30
                request.cachePolicy = .useProtocolCachePolicy
                webView.load(request)
                
                self.lastLoadedURL = restoredURL
                
                DispatchQueue.main.async {
                    tab.url = restoredURL
                }
            }
            
            webView.pageZoom = state.zoomScale
            webView.evaluateJavaScript("window.scrollTo(\(state.scrollX), \(state.scrollY));", completionHandler: nil)
            
            Task { @MainActor [weak self] in
                if let title = state.title {
                    self?.tab?.title = title
                }
                self?.tab?.isHibernated = false
            }
        }

        func restoreHibernatedStateIfNeeded(into webView: WKWebView) {
            guard !isRestoringHibernatedState else { return }
            isRestoringHibernatedState = true
            restoreHibernatedState(into: webView)
            isRestoringHibernatedState = false
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
            self.userContentController(userContentController, didReceive: message)
            replyHandler(nil, nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "passwordBridge" {
                handlePasswordMessage(message)
                return
            }

            guard message.name == webScriptBridge.metadataBridgeName else {
                return
            }

            guard
                let body = message.body as? [String: Any],
                self.tab != nil
            else {
                return
            }

            let title = body["title"] as? String
            let hex = body["themeColor"] as? String
            let faviconString = body["favicon"] as? String

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tab = self.tab else { return }
                if let hoverURL = body["hoverURL"] as? String {
                    let newHoverURL = hoverURL.isEmpty ? nil : hoverURL
                    if tab.hoveredLinkURLString != newHoverURL {
                        tab.hoveredLinkURLString = newHoverURL
                    }
                    return
                }

                if body["hoverURL"] is NSNull {
                    if tab.hoveredLinkURLString != nil {
                        tab.hoveredLinkURLString = nil
                    }
                    return
                }

                if let title, !title.isEmpty, tab.title != title {
                    tab.title = title
                }

                if let hex {
                    let newColor = Color(hex: hex)
                    if tab.themeColor != newColor {
                        tab.themeColor = newColor
                    }
                }

                if let faviconString, let faviconURL = URL(string: faviconString) {
                    Task {
                        await self.loadFavicon(from: faviconURL, for: tab)
                    }
                }
            }
        }

        private func handlePasswordMessage(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let url = message.webView?.url?.absoluteString else { return }
            
            if type == "savePassword" {
                if let user = body["username"] as? String, let pass = body["password"] as? String {
                    DispatchQueue.main.async {
                        PasswordService.shared.savePassword(url: url, username: user, passwordData: pass)
                    }
                }
            } else if type == "fieldsDetected" {
                // Autocomplete if we have passwords
                DispatchQueue.main.async {
                    let passwords = PasswordService.shared.fetchPasswords(for: url)
                    if let first = passwords.first {
                        let script = """
                        (function() {
                            const passField = document.querySelector('input[type="password"]');
                            const userField = document.querySelector('input[type="text"], input[type="email"], input:not([type])');
                            if (passField) passField.value = "\(first.passwordData)";
                            if (userField) userField.value = "\(first.username)";
                        })();
                        """
                        Task {
                             _ = try? await message.webView?.evaluateJavaScript(script)
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.tab?.isLoading = true
                self?.tab?.lastNavigationHadNetworkError = false
                self?.tab?.hoveredLinkURLString = nil
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            self.lastLoadedURL = webView.url
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard self.tab != nil else { return }
            self.lastLoadedURL = webView.url

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tab = self.tab else { return }
                tab.isLoading = false
                tab.title = webView.title ?? tab.title
                tab.hasMixedContentWarning = !webView.hasOnlySecureContent

                if tab.hasMixedContentWarning {
                    AppLog.security("Mixed content warning at \(webView.url?.absoluteString ?? "unknown URL")")
                }

                tab.refreshSnapshot()
            }

            if let lastAppliedStyle {
                applyWebAppearance(to: webView, style: lastAppliedStyle)
            }
            circuitBreaker.reset()

            if let tab = tab, tab.id == tabManager.activeTabID {
                DNSPreFetcher.shared.prefetchLinks(in: webView)
            }

            if let tab = tab {
                let script = """
                (function() {
                    try {
                        const videos = Array.from(document.querySelectorAll('video'));
                        return videos.some(v => {
                            try {
                                return v.readyState >= 2;
                            } catch (_) {
                                return false;
                            }
                        });
                    } catch (e) {
                        return false;
                    }
                })();
                """

                webView.evaluateJavaScript(script) { result, _ in
                    if let hasVideo = result as? Bool {
                        DispatchQueue.main.async {
                            tab.hasPiPCandidate = hasVideo
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if !dohService.shouldAllowRequest(for: url) {
                AppLog.security("Blocked non-HTTP(S) request: \(url.absoluteString)")
                decisionHandler(.cancel)
                return
            }

            if safeBrowsing.isUnsafe(url) {
                AppLog.security("Blocked unsafe URL: \(url.absoluteString)")
                decisionHandler(.cancel)
                return
            }

            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            DownloadManager.shared.addDownload(download)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            DownloadManager.shared.addDownload(download)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                DispatchQueue.main.async { [weak self] in
                    self?.tabManager.createTab(url: navigationAction.request.url)
                }
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: webView.window!) { _ in
                completionHandler()
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: webView.window!) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            input.stringValue = defaultText ?? ""
            alert.accessoryView = input
            
            alert.beginSheetModal(for: webView.window!) { response in
                if response == .alertFirstButtonReturn {
                    completionHandler(input.stringValue)
                } else {
                    completionHandler(nil)
                }
            }
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
            
            openPanel.begin { result in
                if result == .OK {
                    completionHandler(openPanel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }

        func webView(_ webView: WKWebView, contextMenu: NSMenu, forElement elementInfo: Any, completionHandler: @escaping (NSMenu?) -> Void) {
            contextMenuWebView = webView
            contextMenu.addItem(.separator())
            let findItem = NSMenuItem(title: "Find in Page...", action: #selector(triggerFindInPage), keyEquivalent: "f")
            findItem.keyEquivalentModifierMask = .command
            findItem.target = self
            contextMenu.addItem(findItem)

            // This is a hacky way to get the image URL from the context menu
            // I know... I know... I'll fix it later
            if let info = elementInfo as? NSObject, let imageURL = info.value(forKey: "imageURL") as? URL {
                let downloadItem = NSMenuItem(title: "Download Image…", action: #selector(downloadImage(_:)), keyEquivalent: "")
                downloadItem.target = self
                downloadItem.representedObject = imageURL

                let copyItem = NSMenuItem(title: "Copy Image Address", action: #selector(copyImageAddress(_:)), keyEquivalent: "")
                copyItem.target = self
                copyItem.representedObject = imageURL
                contextMenu.addItem(.separator())
                contextMenu.addItem(downloadItem)
                contextMenu.addItem(copyItem)
            }
            completionHandler(contextMenu)
        }

        @objc private func downloadImage(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }

            if #available(macOS 12.0, *), let webView = contextMenuWebView {
                // startDownload is async in newer SDKs; launch a detached task so
                // we can call it from this Objective-C-compatible selector method.
                Task {
                    await webView.startDownload(using: URLRequest(url: url))
                }
            } else {
                DownloadManager.shared.startDownload(from: url)
            }
        }

        @objc private func copyImageAddress(_ sender: NSMenuItem) {
            if let url = sender.representedObject as? URL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }

        @objc private func triggerFindInPage() {
            NotificationCenter.default.post(name: .findInPage, object: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.tab?.isLoading = false
                self?.tab?.lastNavigationHadNetworkError = self?.isNetwork(error: error) ?? false
                self?.tab?.lastNetworkErrorMessage = error.localizedDescription
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard circuitBreaker.canReloadAfterTermination() else {
                DispatchQueue.main.async { [weak self] in
                    self?.tab?.lastNavigationHadNetworkError = true
                    self?.tab?.lastNetworkErrorMessage = "Web process repeatedly crashed. Reload paused by circuit breaker."
                }
                AppLog.info("Circuit breaker prevented reload loop")
                return
            }

            webView.reload()
        }

        private func isNetwork(error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain
        }

        private func loadFavicon(from url: URL, for tab: Tab) async {
            if let cached = faviconCache.image(for: url) {
                DispatchQueue.main.async {
                    tab.favicon = cached
                }
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    faviconCache.set(image, for: url)
                    DispatchQueue.main.async {
                        tab.favicon = image
                    }
                }
            } catch {
                AppLog.info("Failed to load favicon: \(error.localizedDescription)")
            }
        }

        func applyWebAppearance(to webView: WKWebView, style: TabManager.UIStyle) {
            if lastAppliedStyle == style { return }
            lastAppliedStyle = style
            
            let scheme: String
            switch style {
            case .dark:
                scheme = "dark"
            case .light:
                scheme = "light"
            case .system:
                let best = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
                scheme = (best == .darkAqua) ? "dark" : "light"
            }

            let script = """
            (() => {
                const id = "illuminate-force-color-scheme";
                let styleElement = document.getElementById(id);
                if (!styleElement) {
                    styleElement = document.createElement("style");
                    styleElement.id = id;
                    document.documentElement.appendChild(styleElement);
                }
                styleElement.textContent = `
                    :root, html { color-scheme: \(scheme) !important; }
                `;
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func applyContentRules(to webView: WKWebView, ruleList: WKContentRuleList?) {
            guard lastAppliedContentRuleList !== ruleList else { return }
            
            let userContentController = webView.configuration.userContentController
            userContentController.removeAllContentRuleLists()
            if let ruleList = ruleList {
                userContentController.add(ruleList)
            }
            lastAppliedContentRuleList = ruleList
        }
    }
}
