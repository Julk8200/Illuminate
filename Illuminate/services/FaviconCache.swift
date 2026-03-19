//
//  FaviconCache.swift
//  Illuminate
//
//  Created by MrBlankCoding on 3/8/26.
//


import AppKit
import Foundation

// THis works for now but I think I want to build on this later

final class FaviconCache: @unchecked Sendable {
    private enum FaviconFetchError: LocalizedError {
        case unsupportedScheme(String?)
        case invalidDataURL

        var errorDescription: String? {
            switch self {
            case .unsupportedScheme(let scheme):
                return "Unsupported favicon URL scheme: \(scheme ?? "nil")"
            case .invalidDataURL:
                return "Invalid favicon data URL"
            }
        }
    }

    static let shared = FaviconCache(capacity: 128)

    private let capacity: Int
    nonisolated(unsafe) private var storage: [URL: NSImage] = [:]
    nonisolated(unsafe) private var order: [URL] = []
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let cacheURL: URL
    private let fetchData: @Sendable (URL) async throws -> Data
    private let inFlightRequests = AsyncRequestDeduplicator<URL, NSImage?>()

    init(
        capacity: Int,
        cacheDirectory: URL? = nil,
        fetchData: (@Sendable (URL) async throws -> Data)? = nil
    ) {
        self.capacity = max(8, capacity)
        if let fetchData {
            self.fetchData = fetchData
        } else {
            self.fetchData = { url in
                switch url.scheme?.lowercased() {
                case "http", "https":
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return data
                case "data":
                    do {
                        return try Data(contentsOf: url)
                    } catch {
                        throw FaviconFetchError.invalidDataURL
                    }
                default:
                    throw FaviconFetchError.unsupportedScheme(url.scheme)
                }
            }
        }
        
        if let customDir = cacheDirectory {
            self.cacheURL = customDir
        } else {
            let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            let appSupport = paths[0].appendingPathComponent("Illuminate", isDirectory: true)
            cacheURL = appSupport.appendingPathComponent("Favicons", isDirectory: true)
        }
        
        try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    }

    nonisolated func image(for key: URL) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = storage[key] {
            touch(key)
            return cached
        }
        
        // Try disk cache
        if let diskImage = loadFromDisk(key) {
            storage[key] = diskImage
            touch(key)
            return diskImage
        }

        return nil
    }

    nonisolated func fetchImage(for url: URL) async -> NSImage? {
        if let cached = image(for: url) {
            return cached
        }

        do {
            return try await inFlightRequests.value(for: url) { [self] in
                if let cached = image(for: url) {
                    return cached
                }

                let data = try await fetchData(url)
                guard let image = NSImage(data: data) else { return nil }
                set(image, for: url)
                return image
            }
        } catch {
            print("[Illuminate][INFO] Failed to fetch favicon for \(url.absoluteString): \(error.localizedDescription)")
        }
        return nil
    }

    nonisolated func set(_ image: NSImage, for key: URL) {
        lock.lock()
        defer { lock.unlock() }

        storage[key] = image
        touch(key)
        saveToDisk(image, key: key)
        evictIfNeeded()
    }

    nonisolated private func touch(_ key: URL) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    nonisolated private func evictIfNeeded() {
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldest)
            removeFromDisk(oldest)
        }
    }
    
    nonisolated private func diskURL(for key: URL) -> URL {
        let name = key.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return cacheURL.appendingPathComponent(name).appendingPathExtension("png")
    }
    
    nonisolated private func saveToDisk(_ image: NSImage, key: URL) {
        let url = diskURL(for: key)
        Task.detached(priority: .background) {
            let data = await MainActor.run {
                image.pngData()
            }
            if let data = data {
                try? data.write(to: url)
            }
        }
    }
    
    nonisolated private func loadFromDisk(_ key: URL) -> NSImage? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }
    
    nonisolated private func removeFromDisk(_ key: URL) {
        let url = diskURL(for: key)
        try? fileManager.removeItem(at: url)
    }
}
