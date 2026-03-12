//
//  AdBlockService.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/9/26.
//

import Foundation
import Combine
import WebKit

final class AdBlockService: ObservableObject {

    static let shared = AdBlockService()
    
    @Published var isEnabled: Bool = true {
        didSet {
            userDefaults.set(isEnabled, forKey: "adBlockEnabled")
            updateContentRuleList()
        }
    }
    
    @Published private(set) var contentRuleList: WKContentRuleList?
    
    private var blockedHosts: Set<String> = []
    private var blockedURLKeywords: Set<String> = []
    private var allowlistedHosts: Set<String> = []
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.object(forKey: "adBlockEnabled") as? Bool ?? true
        loadDefaultRules()
        
        if isEnabled {
            WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: "IlluminateAdBlockRules") { [weak self] list, _ in
                if let list = list {
                    DispatchQueue.main.async {
                        self?.contentRuleList = list
                    }
                } else {
                    self?.updateContentRuleList()
                }
            }
        }
    }

    private func updateContentRuleList() {
        guard isEnabled else {
            DispatchQueue.main.async { [weak self] in
                self?.contentRuleList = nil
            }
            return
        }

        let rules = generateRulesJSON()
        
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "IlluminateAdBlockRules", encodedContentRuleList: rules) { [weak self] (list: WKContentRuleList?, error: Error?) in
            if let error = error {
                print("Failed to compile adblock rules: \(error.localizedDescription)")
                return
            }
            
            if let contentList = list {
                DispatchQueue.main.async {
                    self?.contentRuleList = contentList
                }
            }
        }
    }

    private func generateRulesJSON() -> String {
        var rulesArray: [[String: Any]] = []
        for host in allowlistedHosts {
            let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
            rulesArray.append([
                "trigger": [
                    "url-filter": ".*\(escapedHost).*",
                    "url-filter-is-case-sensitive": false
                ],
                "action": [
                    "type": "ignore-previous-rules"
                ]
            ])
        }

        for host in blockedHosts {
            let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
            rulesArray.append([
                "trigger": [
                    "url-filter": ".*\(escapedHost).*",
                    "url-filter-is-case-sensitive": false
                ],
                "action": [
                    "type": "block"
                ]
            ])
        }

        for keyword in blockedURLKeywords {
            let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
            rulesArray.append([
                "trigger": [
                    "url-filter": ".*\(escapedKeyword).*",
                    "url-filter-is-case-sensitive": false
                ],
                "action": [
                    "type": "block"
                ]
            ])
        }

        // always include one rule
        // otherwise it gets angryyy
        rulesArray.append([
            "trigger": ["url-filter": "https://illuminate-internal-dummy-rule-to-prevent-error-6.com"],
            "action": ["type": "block"]
        ])

        if let data = try? JSONSerialization.data(withJSONObject: rulesArray, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "[]"
    }

    private func loadDefaultRules() {
        blockedHosts = [
            "doubleclick.net",
            "googlesyndication.com",
            "googleadservices.com",
            "ads.yahoo.com",
            "adservice.google.com",
            "ads-twitter.com",
            "facebook.com",
            "adnxs.com"
        ]

        blockedURLKeywords = [
            "/ads/",
            "banner",
            "advert",
            "tracking",
            "analytics"
        ]

        allowlistedHosts = ["browserbench.org"]
    }

    func updateBlockedHosts(_ hosts: Set<String>) {
        self.blockedHosts = hosts
        self.updateContentRuleList()
    }

    func addAllowlistHost(_ host: String) {
        self.allowlistedHosts.insert(host.lowercased())
        self.updateContentRuleList()
    }
}
