//
//  CookieViewModel.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/9/26.
//

import SwiftUI
import WebKit
import Combine

final class CookieViewModel: ObservableObject {
    @Published var cookies: [HTTPCookie] = []
    @Published var searchText = ""
    @Published var isLoading = true
    var currentDomain: String?

    init(domain: String? = nil) {
        self.currentDomain = domain
    }

    var filteredCookies: [HTTPCookie] {
        let domainFiltered: [HTTPCookie]
        if let domain = currentDomain?.lowercased() {
            domainFiltered = cookies.filter { $0.domain.lowercased().contains(domain) || domain.contains($0.domain.lowercased()) }
        } else {
            domainFiltered = cookies
        }

        if searchText.isEmpty {
            return domainFiltered
        } else {
            return domainFiltered.filter { 
                $0.domain.lowercased().contains(searchText.lowercased()) || 
                $0.name.lowercased().contains(searchText.lowercased()) 
            }
        }
    }

    func clearAllCookies() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom) { [weak self] in
            self?.fetchCookies()
        }
    }

    var groupedCookies: [String: [HTTPCookie]] {
        Dictionary(grouping: filteredCookies, by: { $0.domain })
    }

    var sortedDomains: [String] {
        groupedCookies.keys.sorted()
    }

    func fetchCookies() {
        isLoading = true
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { fetchedCookies in
            DispatchQueue.main.async {
                self.cookies = fetchedCookies
                self.isLoading = false
            }
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) {
        WKWebsiteDataStore.default().httpCookieStore.delete(cookie) { [weak self] in
            self?.fetchCookies()
        }
    }

    func deleteCookies(for domain: String) {
        let cookiesToDelete = cookies.filter { $0.domain == domain }
        let group = DispatchGroup()
        
        for cookie in cookiesToDelete {
            group.enter()
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.fetchCookies()
        }
    }
}
