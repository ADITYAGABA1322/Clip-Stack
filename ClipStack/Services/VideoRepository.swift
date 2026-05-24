//
//  VideoRepository.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import Foundation

struct VideoRepository: Sendable {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadVideos() async throws -> [Video] {
        guard let catalogURL = bundle.url(forResource: "for-you", withExtension: "json")
            ?? bundle.url(forResource: "for-you", withExtension: "json", subdirectory: "Resources")
        else {
            throw RepositoryError.fileNotFound
        }

        let data = try Data(contentsOf: catalogURL)
        let response = try JSONDecoder().decode(VideoCatalog.self, from: data)
        let videos = response.videos.map { video in
            var enriched = video
            enriched.description = VideoDescriptions.text(for: video)
            return enriched
        }

        guard !videos.isEmpty else {
            throw RepositoryError.emptyCatalog
        }

        return videos
    }
}

private struct VideoCatalog: Decodable {
    let videos: [Video]
}

enum RepositoryError: LocalizedError {
    case fileNotFound
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .fileNotFound:  "The bundled for-you.json catalog could not be found."
        case .emptyCatalog:  "The bundled video catalog is empty."
        }
    }
}
