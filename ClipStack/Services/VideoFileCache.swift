//
//  VideoFileCache.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import Foundation

actor VideoFileCache {
    static let shared = VideoFileCache()

    private let directory: URL
    private let maxCachedVideos: Int
    private var inFlightVideoIDs: Set<Int> = []

    init(maxCachedVideos: Int = 5) {
        self.maxCachedVideos = maxCachedVideos
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = baseDirectory.appendingPathComponent("ClipStackVideoCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.trimCache(in: directory, maxCachedVideos: maxCachedVideos)
    }

    func cachedURL(for video: Video) -> URL? {
        let url = fileURL(for: video)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    func schedulePrefetch(_ videos: [Video]) {
        for video in videos {
            let destination = fileURL(for: video)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }

            guard !inFlightVideoIDs.contains(video.id) else {
                continue
            }

            inFlightVideoIDs.insert(video.id)
            Task {
                await download(video)
            }
        }
    }

    private func download(_ video: Video) async {
        defer {
            inFlightVideoIDs.remove(video.id)
            trimCache()
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: video.url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return
            }

            let destination = fileURL(for: video)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
        } catch {
            return
        }
    }

    private func trimCache() {
        Self.trimCache(in: directory, maxCachedVideos: maxCachedVideos)
    }

    private static func trimCache(in directory: URL, maxCachedVideos: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), files.count > maxCachedVideos else {
            return
        }

        let sortedFiles = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        for file in sortedFiles.prefix(files.count - maxCachedVideos) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func fileURL(for video: Video) -> URL {
        directory.appendingPathComponent("\(video.id).mp4", isDirectory: false)
    }
}
