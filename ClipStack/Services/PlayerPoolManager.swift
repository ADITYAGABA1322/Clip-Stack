//
//  PlayerPoolManager.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

@preconcurrency import AVFoundation
import Foundation

actor PlayerPoolManager {
    private let preloadWindowSize: Int
    private let diskCacheWindowSize: Int
    private let fileCache: VideoFileCache
    private var players: [AVPlayer]
    private var slotAssignments: [Int: Int] = [:]
    private var playbackRates: [Int: Float] = [:]
    private var pausedIndexes: Set<Int> = []
    private var currentIndex: Int?

    init(
        preloadWindowSize: Int = 5,
        diskCacheWindowSize: Int = 5,
        isMuted: Bool = false,
        fileCache: VideoFileCache = .shared
    ) {
        self.preloadWindowSize = preloadWindowSize
        self.diskCacheWindowSize = diskCacheWindowSize
        self.fileCache = fileCache
        players = (0..<preloadWindowSize).map { _ in
            let player = AVPlayer()
            player.automaticallyWaitsToMinimizeStalling = false
            player.isMuted = isMuted
            return player
        }
    }

    func setMuted(_ muted: Bool) {
        players.forEach { $0.isMuted = muted }
    }

    func advance(to index: Int, videos: [Video]) async {
        guard videos.indices.contains(index) else { return }

        currentIndex = index
        pausedIndexes.remove(index)
        let targetIndexes = playerWindow(around: index, count: videos.count)
        let cacheIndexes = diskCacheWindow(startingAt: index, count: videos.count)

        releaseSlots(excluding: targetIndexes)
        await assignMissingSlots(for: targetIndexes, videos: videos)
        await fileCache.schedulePrefetch(cacheIndexes.map { videos[$0] })
        prepareWarmPlayers(activeIndex: index)
        applyPlaybackState(activeIndex: index)
    }

    func retry(index: Int, videos: [Video]) async {
        guard videos.indices.contains(index) else { return }

        if let slot = slotAssignments[index] {
            players[slot].replaceCurrentItem(with: await makeItem(for: videos[index]))
            applyPlaybackState(activeIndex: currentIndex ?? index)
        } else {
            await advance(to: index, videos: videos)
        }
    }

    func player(for index: Int) -> AVPlayer? {
        guard let slot = slotAssignments[index] else { return nil }
        return players[slot]
    }

    func pauseAll() {
        players.forEach { $0.pause() }
    }

    func resumeCurrent() {
        guard let currentIndex, let slot = slotAssignments[currentIndex] else { return }
        guard !pausedIndexes.contains(currentIndex) else { return }
        players[slot].playImmediately(atRate: playbackRates[currentIndex] ?? 1)
    }

    func setPaused(_ isPaused: Bool, at index: Int) {
        guard let slot = slotAssignments[index] else { return }

        if isPaused {
            pausedIndexes.insert(index)
            players[slot].pause()
        } else {
            pausedIndexes.remove(index)
            players[slot].playImmediately(atRate: playbackRates[index] ?? 1)
        }
    }

    func setPlaybackRate(_ rate: Float, at index: Int) {
        playbackRates[index] = rate

        guard currentIndex == index, !pausedIndexes.contains(index), let slot = slotAssignments[index] else {
            return
        }

        players[slot].rate = rate
    }

    func seek(to seconds: Double, at index: Int) {
        guard let slot = slotAssignments[index] else { return }

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        players[slot].seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func liveSeek(to seconds: Double, at index: Int) {
        guard let slot = slotAssignments[index] else { return }
        let tolerance = CMTime(seconds: 0.3, preferredTimescale: 600)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        players[slot].seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func skip(by seconds: Double, at index: Int) {
        guard let slot = slotAssignments[index] else { return }

        let player = players[slot]
        let currentSeconds = player.currentTime().seconds
        let durationSeconds = player.currentItem?.duration.seconds ?? .zero
        let upperBound = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : max(currentSeconds + seconds, 0)
        let target = min(max(currentSeconds + seconds, 0), upperBound)
        let time = CMTime(seconds: target, preferredTimescale: 600)

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func playerWindow(around index: Int, count: Int) -> [Int] {
        var lowerBound = max(index - 1, 0)
        var upperBound = min(lowerBound + preloadWindowSize - 1, count - 1)
        lowerBound = max(min(lowerBound, upperBound - preloadWindowSize + 1), 0)
        upperBound = min(lowerBound + preloadWindowSize - 1, count - 1)
        return Array(lowerBound...upperBound)
    }

    private func diskCacheWindow(startingAt index: Int, count: Int) -> [Int] {
        let upperBound = min(index + diskCacheWindowSize - 1, count - 1)
        return Array(index...upperBound)
    }

    private func releaseSlots(excluding targetIndexes: [Int]) {
        let keep = Set(targetIndexes)
        let staleAssignments = slotAssignments.filter { videoIndex, _ in
            !keep.contains(videoIndex)
        }

        for (videoIndex, slot) in staleAssignments {
            players[slot].pause()
            players[slot].replaceCurrentItem(with: nil)
            slotAssignments.removeValue(forKey: videoIndex)
            playbackRates.removeValue(forKey: videoIndex)
            pausedIndexes.remove(videoIndex)
        }
    }

    private func assignMissingSlots(for targetIndexes: [Int], videos: [Video]) async {
        var availableSlots = (0..<players.count).filter { slot in
            !slotAssignments.values.contains(slot)
        }

        for videoIndex in targetIndexes where slotAssignments[videoIndex] == nil {
            guard let slot = availableSlots.first else { return }
            availableSlots.removeFirst()

            players[slot].replaceCurrentItem(with: await makeItem(for: videos[videoIndex]))
            slotAssignments[videoIndex] = slot
        }
    }

    private func makeItem(for video: Video) async -> AVPlayerItem {
        let playbackURL = await fileCache.cachedURL(for: video) ?? video.url
        let item = AVPlayerItem(url: playbackURL)
        item.preferredForwardBufferDuration = 6
        return item
    }

    private func prepareWarmPlayers(activeIndex: Int) {
        for (videoIndex, slot) in slotAssignments where videoIndex != activeIndex {
            let player = players[slot]
            player.currentItem?.preferredForwardBufferDuration = 6

            guard player.status == .readyToPlay,
                  player.currentItem?.status == .readyToPlay
            else {
                continue
            }

            player.preroll(atRate: 1)
        }
    }

    private func applyPlaybackState(activeIndex: Int) {
        for (videoIndex, slot) in slotAssignments {
            if videoIndex == activeIndex, !pausedIndexes.contains(videoIndex) {
                players[slot].playImmediately(atRate: playbackRates[videoIndex] ?? 1)
            } else {
                players[slot].pause()
            }
        }
    }
}
