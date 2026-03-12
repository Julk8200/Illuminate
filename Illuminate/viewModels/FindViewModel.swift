//
//  FindViewModel.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/11/26.
//

import SwiftUI
import WebKit
import Combine

@MainActor
final class FindViewModel: ObservableObject {
    @Published var searchText = "" {
        didSet {
            if searchText.isEmpty {
                clearResults()
            } else if searchText != oldValue {
                findNext()
            }
        }
    }
    @Published var isPresented = false {
        didSet {
            if !isPresented {
                clearResults()
            }
        }
    }
    @Published var matchFound = false
    
    private weak var webView: WKWebView?
    
    func setWebView(_ webView: WKWebView?) {
        self.webView = webView
    }
    
    func findNext() {
        performFind(forward: true)
    }
    
    func findPrevious() {
        performFind(forward: false)
    }
    
    private func performFind(forward: Bool) {
        guard let webView = webView, !searchText.isEmpty else { return }
        
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.wraps = true
        
        webView.find(searchText, configuration: configuration) { [weak self] result in
            DispatchQueue.main.async {
                self?.matchFound = result.matchFound
            }
        }
    }
    
    private func clearResults() {
        matchFound = false
    }
    
    func dismiss() {
        isPresented = false
        searchText = ""
    }
}
