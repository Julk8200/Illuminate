//
//  SafeBrowsingManager.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//

// AGAIN!
// This really is just a placeholder right now
// malware.test lolllll
import Foundation

final class SafeBrowsingManager {
    static let shared = SafeBrowsingManager()

    private let blockedHosts: Set<String> = [
        "malware.test",
        "phishing.test"
    ]

    private init() {}

    func isUnsafe(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return blockedHosts.contains(host)
    }
}
