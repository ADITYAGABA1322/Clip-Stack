//
//  VideoOverlayView.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import SwiftUI

struct VideoOverlayView: View {
    let video: Video

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                Text(video.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)

                Text(video.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                    Text(video.formattedDuration)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.leading, 16)
            .padding(.trailing, 84)
            .padding(.bottom, 48)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    VideoOverlayView(
        video: Video(
            id: 1,
            title: "Scenic View Of The Sunset",
            duration: 181,
            width: 1080,
            height: 1920,
            url: URL(string: "https://example.com/video.mp4")!,
            thumbnail: URL(string: "https://example.com/poster.jpg")!,
            description: "The sky burns softly before the last light slips away."
        )
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
