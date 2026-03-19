//
//  NavigationPreconnectManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/18/26.
//

import Foundation
import WebKit

@MainActor
final class NavigationPreconnectManager {
    static let shared = NavigationPreconnectManager()

    private var lastPreconnectedAt: [String: Date] = [:]
    private let cooldown: TimeInterval = 20

    private init() {}

    func preconnect(to url: URL, in webView: WKWebView?) {
        guard
            let webView,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else { return }

        let origin = originString(for: url)
        let now = Date()
        if let last = lastPreconnectedAt[origin], now.timeIntervalSince(last) < cooldown {
            return
        }

        lastPreconnectedAt[origin] = now
        DNSPreFetcher.shared.prefetchHost(host)

        guard
            let originJSON = jsonStringLiteral(origin),
            let dnsJSON = jsonStringLiteral("//\(host)")
        else { return }

        let script = """
        (() => {
            const head = document.head || document.documentElement;
            const ensure = (rel, href, crossOrigin) => {
                const key = `${rel}:${href}`;
                let el = head.querySelector(`link[data-illuminate-preconnect="${key}"]`);
                if (!el) {
                    el = document.createElement('link');
                    el.dataset.illuminatePreconnect = key;
                    el.rel = rel;
                    el.href = href;
                    if (crossOrigin) el.crossOrigin = 'anonymous';
                    head.appendChild(el);
                }
            };
            ensure('dns-prefetch', \(dnsJSON), false);
            ensure('preconnect', \(originJSON), true);
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func originString(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func jsonStringLiteral(_ string: String) -> String? {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [string]),
            let json = String(data: data, encoding: .utf8)
        else { return nil }

        return String(json.dropFirst().dropLast())
    }
}
