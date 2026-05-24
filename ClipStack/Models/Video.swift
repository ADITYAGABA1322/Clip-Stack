//
//  Video.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import Foundation

struct Video: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let duration: Int
    let width: Int
    let height: Int
    let url: URL
    let thumbnail: URL
    var description: String

    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    init(
        id: Int,
        title: String,
        duration: Int,
        width: Int,
        height: Int,
        url: URL,
        thumbnail: URL,
        description: String = ""
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.width = width
        self.height = height
        self.url = url
        self.thumbnail = thumbnail
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, duration, width, height, url, thumbnail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        duration = try container.decode(Int.self, forKey: .duration)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        url = try container.decode(URL.self, forKey: .url)
        thumbnail = try container.decode(URL.self, forKey: .thumbnail)
        description = ""
    }
}
