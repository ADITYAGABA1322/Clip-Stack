//
//  ClipStackTests.swift
//  ClipStackTests
//
//  Created by Aditya Gaba on 5/23/26.
//

import Foundation
import Testing
@testable import ClipStack

// MARK: - Helpers

private func makeVideo(id: Int, title: String = "Test Video", duration: Int = 120) -> Video {
    Video(
        id: id,
        title: title,
        duration: duration,
        width: 720,
        height: 1280,
        url: URL(string: "https://videos.pexels.com/video-files/\(id)/\(id).mp4")!,
        thumbnail: URL(string: "https://images.pexels.com/videos/\(id)/poster.jpeg")!
    )
}

private func make60Videos() -> [Video] {
    (0..<60).map { makeVideo(id: $0, title: "Video \($0)") }
}

// MARK: - Video Model

struct VideoModelTests {

    @Test func durationFormattingPadsSeconds() throws {
        let v = makeVideo(id: 1, duration: 61)
        #expect(v.formattedDuration == "1:01")
    }

    @Test func durationFormattingZero() throws {
        let v = makeVideo(id: 1, duration: 0)
        #expect(v.formattedDuration == "0:00")
    }

    @Test func durationFormattingLong() throws {
        let v = makeVideo(id: 1, duration: 236)
        #expect(v.formattedDuration == "3:56")
    }

    @Test func descriptionFallbackIsNonEmpty() throws {
        let v = makeVideo(id: -999)
        #expect(VideoDescriptions.text(for: v).isEmpty == false)
    }

    @Test func descriptionKnownIDIsSpecific() throws {
        let v = makeVideo(id: 11187395)
        let desc = VideoDescriptions.text(for: v)
        #expect(desc != "A quiet visual moment captured in motion.")
        #expect(desc.isEmpty == false)
    }
}

// MARK: - FeedComment Backward-Compatible Decoding

struct FeedCommentDecodingTests {

    @Test func legacyCommentDecodesWithDefaults() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "author": "Alice",
          "text": "Great video!",
          "colorIndex": 1
        }
        """.data(using: .utf8)!

        let comment = try JSONDecoder().decode(FeedComment.self, from: json)
        #expect(comment.author == "Alice")
        #expect(comment.text == "Great video!")
        #expect(comment.likes == 0)
        #expect(comment.isLiked == false)
        #expect(comment.timestamp == "1d")
        #expect(comment.replies.isEmpty)
    }

    @Test func modernCommentDecodesAllFields() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "author": "Bob",
          "text": "Amazing clip",
          "colorIndex": 2,
          "likes": 42,
          "isLiked": true,
          "timestamp": "3h",
          "replies": []
        }
        """.data(using: .utf8)!

        let comment = try JSONDecoder().decode(FeedComment.self, from: json)
        #expect(comment.likes == 42)
        #expect(comment.isLiked == true)
        #expect(comment.timestamp == "3h")
    }

    @Test func initialsExtractFirstTwo() {
        let comment = FeedComment(author: "Alex Morgan", text: "", colorIndex: 0)
        #expect(comment.initials == "AM")
    }

    @Test func initialsSingleName() {
        let comment = FeedComment(author: "Madonna", text: "", colorIndex: 0)
        #expect(comment.initials == "M")
    }

    @Test func initialsEmptyAuthorFallback() {
        let comment = FeedComment(author: "", text: "", colorIndex: 0)
        #expect(comment.initials == "?")
    }
}

// MARK: - CommentReply Decoding

struct CommentReplyDecodingTests {

    @Test func legacyReplyDecodesWithIsLikedFalse() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789abc",
          "author": "Carol",
          "text": "Nice!",
          "colorIndex": 0,
          "likes": 5,
          "timestamp": "1h"
        }
        """.data(using: .utf8)!

        let reply = try JSONDecoder().decode(CommentReply.self, from: json)
        #expect(reply.isLiked == false)
        #expect(reply.likes == 5)
    }
}

// MARK: - FeedViewModel Social State

@Suite(.serialized)
struct FeedViewModelSocialTests {

    @Test @MainActor func toggleLikeIncrements() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 99)
        let before = vm.socialState(for: video).likeCount
        vm.toggleLike(for: video)
        #expect(vm.socialState(for: video).likeCount == before + 1)
        #expect(vm.socialState(for: video).isLiked == true)
    }

    @Test @MainActor func toggleLikeDecrements() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 98)
        vm.toggleLike(for: video)
        let afterLike = vm.socialState(for: video).likeCount
        vm.toggleLike(for: video)
        #expect(vm.socialState(for: video).likeCount == afterLike - 1)
        #expect(vm.socialState(for: video).isLiked == false)
    }

    @Test @MainActor func likeIdempotent() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 97)
        vm.like(for: video)
        let afterFirst = vm.socialState(for: video).likeCount
        vm.like(for: video)
        #expect(vm.socialState(for: video).likeCount == afterFirst)
        #expect(vm.socialState(for: video).isLiked == true)
    }

    @Test @MainActor func toggleBookmarkChangesState() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 96)
        let before = vm.socialState(for: video).bookmarkCount
        vm.toggleBookmark(for: video)
        #expect(vm.socialState(for: video).isBookmarked == true)
        #expect(vm.socialState(for: video).bookmarkCount == before + 1)
        vm.toggleBookmark(for: video)
        #expect(vm.socialState(for: video).isBookmarked == false)
        #expect(vm.socialState(for: video).bookmarkCount == before)
    }

    @Test @MainActor func recordShareIncrements() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 95)
        let before = vm.socialState(for: video).shareCount
        vm.recordShare(for: video)
        #expect(vm.socialState(for: video).shareCount == before + 1)
    }

    @Test @MainActor func addCommentPrependsToList() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 94)
        let before = vm.socialState(for: video).comments.count
        vm.addComment("Hello feed!", for: video)
        let after = vm.socialState(for: video).comments
        #expect(after.count == before + 1)
        #expect(after.first?.text == "Hello feed!")
        #expect(after.first?.author == "You")
    }

    @Test @MainActor func addReplyAppendsToComment() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 93)
        vm.addComment("Parent comment", for: video)
        let commentID = vm.socialState(for: video).comments.first!.id
        let didAdd = vm.addReply("My reply", to: commentID, for: video)
        #expect(didAdd == true)
        let replies = vm.socialState(for: video).comments.first!.replies
        #expect(replies.last?.text == "My reply")
        #expect(replies.last?.author == "You")
    }

    @Test @MainActor func addReplyToNonExistentCommentReturnsFalse() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 92)
        let fakeID = UUID()
        let didAdd = vm.addReply("Ghost reply", to: fakeID, for: video)
        #expect(didAdd == false)
    }

    @Test @MainActor func toggleCommentLikeToggles() {
        let vm = FeedViewModel()
        let video = makeVideo(id: 91)
        vm.addComment("Like me", for: video)
        let commentID = vm.socialState(for: video).comments.first!.id
        let isLikedNow = vm.toggleCommentLike(commentID, for: video)
        #expect(isLikedNow == true)
        #expect(vm.socialState(for: video).comments.first!.isLiked == true)
        let isLikedAfterUnlike = vm.toggleCommentLike(commentID, for: video)
        #expect(isLikedAfterUnlike == false)
    }
}

// MARK: - FeedViewModel Gesture Guide

struct FeedViewModelGestureTests {

    @Test @MainActor func gestureGuideShownOnlyForIndexZero() {
        let vm = FeedViewModel()
        #expect(vm.shouldShowGestureGuide(at: 0) == !vm.hasSeenGestureGuide)
        #expect(vm.shouldShowGestureGuide(at: 1) == false)
        #expect(vm.shouldShowGestureGuide(at: 10) == false)
    }

    @Test @MainActor func markGestureGuideSeenPreventsReshow() {
        let vm = FeedViewModel()
        vm.hasSeenGestureGuide = false           // reset for test isolation
        vm.markGestureGuideSeen()
        #expect(vm.hasSeenGestureGuide == true)
        #expect(vm.shouldShowGestureGuide(at: 0) == false)
    }
}

// MARK: - FeedViewModel Load State

struct FeedViewModelLoadStateTests {

    @Test @MainActor func initialLoadStateIsIdle() {
        let vm = FeedViewModel()
        #expect(vm.loadState == .idle)
        #expect(vm.videos.isEmpty)
    }
}

// MARK: - PlayerPoolManager Slot Bounds

struct PlayerPoolManagerTests {

    @Test func advancingFarReleaseEarlySlots() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5)
        let videos = make60Videos()

        await pool.advance(to: 0, videos: videos)
        await pool.advance(to: 30, videos: videos)

        let playerFor0 = await pool.player(for: 0)
        #expect(playerFor0 == nil, "Slot for index 0 should be released after advancing to 30")
    }

    @Test func currentIndexAlwaysHasPlayer() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5)
        let videos = make60Videos()

        for targetIndex in [0, 5, 15, 30, 55, 59] {
            await pool.advance(to: targetIndex, videos: videos)
            let p = await pool.player(for: targetIndex)
            #expect(p != nil, "Index \(targetIndex) should always have a player after advance")
        }
    }

    @Test func windowBoundsAreCorrect() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5)
        let videos = make60Videos()
        let target = 20

        await pool.advance(to: target, videos: videos)

        for i in 19...23 {
            let p = await pool.player(for: i)
            #expect(p != nil, "Index \(i) should be in window around \(target)")
        }
        for i in [0, 10, 18, 25, 50] {
            let p = await pool.player(for: i)
            #expect(p == nil, "Index \(i) should NOT be in window around \(target)")
        }
    }

    @Test func scrollingThrough60VideosStaysStable() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5)
        let videos = make60Videos()

        for i in 0..<60 {
            await pool.advance(to: i, videos: videos)
        }

        let last = await pool.player(for: 59)
        #expect(last != nil)
    }

    @Test func outOfRangeIndexReturnsNil() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5)
        let videos = make60Videos()
        await pool.advance(to: 0, videos: videos)

        let p1 = await pool.player(for: -1)
        let p2 = await pool.player(for: 999)
        #expect(p1 == nil)
        #expect(p2 == nil)
    }

    @Test func mutePropagates() async {
        let pool = PlayerPoolManager(preloadWindowSize: 5, isMuted: false)
        await pool.setMuted(true)
        await pool.setMuted(false)
    }
}

// MARK: - Catalog Size

struct CatalogTests {

    @Test func catalogHasAtLeast50Videos() async throws {
        let repo = VideoRepository()
        let videos = try await repo.loadVideos()
        #expect(videos.count >= 50, "Catalog must have ≥ 50 videos for memory stress testing")
    }

    @Test func catalogHasNoDuplicateIDs() async throws {
        let repo = VideoRepository()
        let videos = try await repo.loadVideos()
        let ids = videos.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count, "Every video entry must have a unique ID")
    }

    @Test func catalogAllURLsWellFormed() async throws {
        let repo = VideoRepository()
        let videos = try await repo.loadVideos()
        for video in videos {
            #expect(video.url.scheme == "https", "Video \(video.id) URL must be HTTPS")
            #expect(video.thumbnail.scheme == "https", "Video \(video.id) thumbnail must be HTTPS")
        }
    }
}

// MARK: - Social State Persistence Round-trip

struct SocialStatePersistenceTests {

    @Test @MainActor func socialStateRoundTripViaJSON() throws {
        let original = FeedSocialState(
            likeCount: 500,
            bookmarkCount: 120,
            shareCount: 30,
            comments: [
                FeedComment(author: "Alice", text: "Nice", colorIndex: 0,
                            likes: 10, isLiked: true, timestamp: "2h",
                            replies: [
                                CommentReply(author: "Bob", text: "Agreed", colorIndex: 1,
                                             likes: 3, isLiked: false, timestamp: "1h")
                            ])
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeedSocialState.self, from: data)

        #expect(decoded.likeCount == 500)
        #expect(decoded.isLiked == false)
        #expect(decoded.comments.count == 1)
        #expect(decoded.comments[0].author == "Alice")
        #expect(decoded.comments[0].isLiked == true)
        #expect(decoded.comments[0].replies.count == 1)
        #expect(decoded.comments[0].replies[0].author == "Bob")
    }
}
