//
//  EasyListParser.swift
//  Illuminate
//  Created by MrBlankCoding on 3/18/26.
//

import Foundation

final class EasyListParser {

    static func parse(content: String, limit: Int = 45000) -> String {
        let lines = content.components(separatedBy: .newlines)
        var rules: [[String: Any]] = []
        
        let typeMap: [String: String] = [
            "image": "image",
            "script": "script",
            "stylesheet": "style-sheet",
            "subdocument": "document",
            "font": "font",
            "media": "media",
            "xmlhttprequest": "raw",
            "websocket": "raw",
            "other": "raw",
            "ping": "ping",
            "popup": "popup"
        ]

        for line in lines {
            if rules.count >= limit { break }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[Adblock") {
                continue
            }
            
            var isException = false
            var currentRuleLine = trimmed
            
            if currentRuleLine.hasPrefix("@@") {
                isException = true
                currentRuleLine = String(currentRuleLine.dropFirst(2))
            }

            if isException {
                continue
            }
            
            // Element hiding: ##.selector or ###id
            if currentRuleLine.contains("##") {
                let parts = currentRuleLine.components(separatedBy: "##")
                if parts.count == 2 {
                    let domainStr = parts[0]
                    let selector = parts[1]
                    
                    var trigger: [String: Any] = ["url-filter": ".*"]
                    if !domainStr.isEmpty {
                        let domains = domainStr.components(separatedBy: ",")
                        let (ifDomains, unlessDomains) = splitDomains(domains)
                        if !ifDomains.isEmpty { trigger["if-domain"] = ifDomains }
                        if !unlessDomains.isEmpty { trigger["unless-domain"] = unlessDomains }
                    }
                    
                    rules.append([
                        "trigger": trigger,
                        "action": [
                            "type": "css-display-none",
                            "selector": selector
                        ]
                    ])
                }
                continue
            }
            
            let parts = currentRuleLine.components(separatedBy: "$")
            let filter = parts[0]
            var trigger: [String: Any] = [:]

            trigger["url-filter"] = convertToRegex(filter)
            
            if parts.count > 1 {
                let options = parts[1].components(separatedBy: ",")
                var resourceTypes: [String] = []
                var hasExclusionOption = false
                
                for opt in options {
                    if opt == "third-party" {
                        trigger["load-type"] = ["third-party"]
                    } else if opt == "first-party" {
                        trigger["load-type"] = ["first-party"]
                    } else if opt.hasPrefix("domain=") {
                        // Domain modifiers are intentionally ignored until the parser
                        // can translate the full EasyList semantics into Safari rules.
                    } else if let safariType = typeMap[opt] {
                        resourceTypes.append(safariType)
                    } else if opt.hasPrefix("~") {
                        hasExclusionOption = true
                    }
                }
                
                if !resourceTypes.isEmpty {
                    trigger["resource-type"] = resourceTypes
                }
                
                if hasExclusionOption && !isException {
                    // need to implement
                }
            }
            
            rules.append([
                "trigger": trigger,
                "action": ["type": "block"]
            ])
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "[]"
    }
    
    private static func splitDomains(_ domains: [String]) -> (ifDomains: [String], unlessDomains: [String]) {
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        for d in domains {
            if d.hasPrefix("~") {
                unlessDomains.append(String(d.dropFirst()))
            } else if !d.isEmpty {
                ifDomains.append(d)
            }
        }
        return (ifDomains, unlessDomains)
    }
    
    private static func convertToRegex(_ filter: String) -> String {
        var regex = filter
        
        // Handle || prefix (domain boundary)
        if regex.hasPrefix("||") {
            var domainPart = regex.dropFirst(2)
            if domainPart.hasSuffix("^") {
                domainPart = domainPart.dropLast()
            }
            regex = ".*" + domainPart.replacingOccurrences(of: ".", with: "\\.") + ".*"
        } else {
            regex = NSRegularExpression.escapedPattern(for: regex)
                .replacingOccurrences(of: "\\*", with: ".*")
        }
        // need a better implementation but im lazy
        regex = regex.replacingOccurrences(of: "\\^", with: "")
        
        return regex
    }
}
