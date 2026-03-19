//
//  FaviconCacheTests.swift
//  IlluminateTests
//
//  Created by MrBlankCoding on 3/11/26.
//

import Testing
import AppKit
import Foundation
@testable import Illuminate

@MainActor
struct FaviconCacheTests {

    private func createTestImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.blue.set()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    private func temporaryCacheDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testLRUEviction() async throws {
        let cacheDir = temporaryCacheDirectory()
        let cache = FaviconCache(capacity: 8, cacheDirectory: cacheDir) // min capacity is 8
        
        let urls = (1...9).map { URL(string: "https://site\($0).com")! }
        let img = createTestImage()
        
        for url in urls.prefix(8) {
            cache.set(img, for: url)
        }
        
        _ = cache.image(for: urls[0])
        cache.set(img, for: urls[8])
        
        #expect(cache.image(for: urls[0]) != nil, "urls[0] should still be cached")
        #expect(cache.image(for: urls[1]) == nil, "urls[1] should be evicted")
        
        try? FileManager.default.removeItem(at: cacheDir)
    }

    @Test func testCacheSetAndGet() async throws {
        let cacheDir = temporaryCacheDirectory()
        let cache = FaviconCache(capacity: 10, cacheDirectory: cacheDir)
        let url = URL(string: "https://example.com/favicon.ico")!
        
        #expect(cache.image(for: url) == nil, "Cache should be empty initially")
        
        let img = createTestImage()
        cache.set(img, for: url)
        
        let retrieved = cache.image(for: url)
        #expect(retrieved != nil, "Cached image should be retrievable")
        
        try? FileManager.default.removeItem(at: cacheDir)
    }

    @Test func testDiskPersistence() async throws {
        let cacheDir = temporaryCacheDirectory()
        let cache = FaviconCache(capacity: 10, cacheDirectory: cacheDir)
        let url = URL(string: "https://persist-test.com")!
        
        let img = createTestImage()
        cache.set(img, for: url)
        
        try await Task.sleep(nanoseconds: 200_000_000)
        let newCache = FaviconCache(capacity: 10, cacheDirectory: cacheDir)
        let retrieved = newCache.image(for: url)
        
        #expect(retrieved != nil, "Image should persist across cache instances via disk")

        try? FileManager.default.removeItem(at: cacheDir)
    }

    @Test func testConcurrentFetchesAreDeduplicated() async throws {
        let cacheDir = temporaryCacheDirectory()
        let url = URL(string: "https://example.com/favicon.ico")!
        let data = createTestImage().pngData()!
        let counter = LockedCounter()

        let cache = FaviconCache(
            capacity: 10,
            cacheDirectory: cacheDir,
            fetchData: { _ in
                counter.increment()
                try await Task.sleep(nanoseconds: 100_000_000)
                return data
            }
        )

        async let first = cache.fetchImage(for: url)
        async let second = cache.fetchImage(for: url)
        let firstResult = await first
        let secondResult = await second

        #expect(firstResult != nil)
        #expect(secondResult != nil)
        #expect(counter.value == 1, "Concurrent favicon fetches should coalesce into one request")

        try? FileManager.default.removeItem(at: cacheDir)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
