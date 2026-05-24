//
//  ClipStackApp.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import AVFoundation
import SwiftUI

@main
struct ClipStackApp: App {
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            FeedView()
                .preferredColorScheme(.dark)
        }
    }
}
