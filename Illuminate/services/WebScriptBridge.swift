//
//  WebScriptBridge.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

import Foundation
import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class WebScriptBridge {

    static let shared = WebScriptBridge()
    private init() {}
    let metadataBridgeName = "metadataBridge"
    let passwordBridgeName = "passwordBridge"

    func installScripts(
        on contentController: WKUserContentController,
        handler: WKScriptMessageHandler
    ) {
        removeAll(from: contentController)

        let weakHandler = WeakScriptMessageHandler(handler)
        contentController.add(weakHandler, name: metadataBridgeName)
        contentController.add(weakHandler, name: passwordBridgeName)

        contentController.addUserScript(metadataExtractionScript())
        contentController.addUserScript(hoverTrackingScript())
        contentController.addUserScript(passwordScript())
    }

    func removeAll(from contentController: WKUserContentController) {
        contentController.removeAllUserScripts()
        contentController.removeScriptMessageHandler(forName: metadataBridgeName)
        contentController.removeScriptMessageHandler(forName: passwordBridgeName)
    }

    private func metadataExtractionScript() -> WKUserScript {
        let source = """
        (() => {
            const faviconEl = document.querySelector('link[rel~="icon"]');
            const themeEl   = document.querySelector('meta[name="theme-color"]');
            try {
                window.webkit.messageHandlers.\(metadataBridgeName).postMessage({
                    favicon:    faviconEl ? faviconEl.href    : null,
                    themeColor: themeEl   ? themeEl.content  : null,
                    title:      document.title
                });
            } catch (_) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    private func hoverTrackingScript() -> WKUserScript {
        let source = """
        (() => {
            if (window.__illuminateHoverInstalled) return;
            window.__illuminateHoverInstalled = true;

            function postHover(value) {
                if (value === window.__illuminateLastHover) return;
                window.__illuminateLastHover = value;
                try {
                    window.webkit.messageHandlers.\(metadataBridgeName).postMessage({ hoverURL: value });
                } catch (_) {}
            }

            document.addEventListener('mouseover', (e) => {
                const link = e.target?.closest?.('a[href]');
                postHover(link ? link.href : null);
            }, { passive: true });

            document.addEventListener('mouseout', (e) => {
                if (!e.relatedTarget?.closest?.('a[href]')) postHover(null);
            }, { passive: true });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private func passwordScript() -> WKUserScript {
        let source = """
        (() => {
            if (window.__illuminatePasswordInstalled) return;
            window.__illuminatePasswordInstalled = true;

            function notifyFieldsDetected() {
                try {
                    window.webkit.messageHandlers.\(passwordBridgeName).postMessage({ type: 'fieldsDetected' });
                } catch (_) {}
            }

            function checkForPasswordFields() {
                if (document.querySelector('input[type="password"]')) {
                    notifyFieldsDetected();
                }
            }

            checkForPasswordFields();
            const observer = new MutationObserver(() => checkForPasswordFields());
            observer.observe(document.body, { childList: true, subtree: true });

            document.addEventListener('submit', (e) => {
                const form = e.target;
                const passwordField = form.querySelector('input[type="password"]');
                const userField     = form.querySelector(
                    'input[type="text"], input[type="email"], input:not([type])'
                );
                if (!passwordField || !userField) return;

                try {
                    window.webkit.messageHandlers.\(passwordBridgeName).postMessage({
                        type:     'savePassword',
                        username: userField.value,
                        password: passwordField.value
                    });
                } catch (_) {}
            }, true);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
}