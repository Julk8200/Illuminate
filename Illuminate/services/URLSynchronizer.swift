//
//  URLSynchronizer.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//


import Combine
import Foundation

final class URLSynchronizer: ObservableObject {
    static let shared = URLSynchronizer()

    @Published private(set) var currentURL: URL?

    private init() {}

    func updateCurrentURL(_ url: URL?) {
        DispatchQueue.main.async {
            self.currentURL = url
        }
    }
}
