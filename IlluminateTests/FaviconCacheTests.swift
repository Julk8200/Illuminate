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
        
        // Touch the 1st one so it moves to end
        _ = cache.image(for: urls[0])
        
        // 9th should kick the 2nd one (which is now the oldest)
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
}
