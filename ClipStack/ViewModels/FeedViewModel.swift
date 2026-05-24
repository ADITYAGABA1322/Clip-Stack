//
//  FeedViewModel.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

@preconcurrency import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    var videos: [Video] = []
    var currentIndex = 0
    var loadState: LoadState = .idle
    var playerGeneration = 0
    var isMuted: Bool = false
    var socialStates: [Int: FeedSocialState] = [:]
    var hasSeenGestureGuide = false

    @ObservationIgnored private let repository: VideoRepository
    @ObservationIgnored private let playerPool: PlayerPoolManager
    @ObservationIgnored private var poolTask: Task<Void, Never>?
    @ObservationIgnored private var poolRevision = 0
    @ObservationIgnored private static let muteKey = "clipstack.isMuted"
    @ObservationIgnored private static let socialStateKey = "clipstack.socialStates"
    @ObservationIgnored private static let commentCopyVersionKey = "clipstack.commentCopyVersion"
    @ObservationIgnored private static let gestureGuideKey = "clipstack.hasSeenGestureGuide.v2"
    @ObservationIgnored private static let currentCommentCopyVersion = 2

    init(
        repository: VideoRepository? = nil,
        playerPool: PlayerPoolManager? = nil
    ) {
        let savedMuted = UserDefaults.standard.object(forKey: Self.muteKey) as? Bool ?? true
        isMuted = savedMuted
        socialStates = Self.loadSocialStates()
        hasSeenGestureGuide = UserDefaults.standard.bool(forKey: Self.gestureGuideKey)
        self.repository = repository ?? VideoRepository()
        self.playerPool = playerPool ?? PlayerPoolManager(isMuted: savedMuted)
    }

    func load() async {
        guard videos.isEmpty, loadState != .loading else { return }

        loadState = .loading

        do {
            let loadedVideos = try await repository.loadVideos()
            videos = loadedVideos
            currentIndex = 0
            refreshGeneratedCommentsIfNeeded(for: loadedVideos)

            await playerPool.advance(to: 0, videos: loadedVideos)
            FeedPerformanceMonitor.pageSettled(index: 0, total: loadedVideos.count)
            loadState = .loaded
            playerGeneration += 1
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func onPageChanged(to index: Int) {
        guard videos.indices.contains(index) else {
            return
        }

        currentIndex = index
        FeedPerformanceMonitor.pageSettled(index: index, total: videos.count)
        syncPool(to: index)
    }

    func setPaused(_ isPaused: Bool, at index: Int) {
        Task { [playerPool] in
            await playerPool.setPaused(isPaused, at: index)
        }
    }

    func setPlaybackRate(_ rate: Float, at index: Int) {
        Task { [playerPool] in
            await playerPool.setPlaybackRate(rate, at: index)
        }
    }

    func seek(to seconds: Double, at index: Int) {
        Task { [playerPool] in
            await playerPool.seek(to: seconds, at: index)
        }
    }

    func liveSeek(to seconds: Double, at index: Int) {
        Task { [playerPool] in
            await playerPool.liveSeek(to: seconds, at: index)
        }
    }

    func skip(by seconds: Double, at index: Int) {
        Task { [playerPool] in
            await playerPool.skip(by: seconds, at: index)
        }
    }

    func retryCatalogLoad() {
        Task { [weak self] in
            await self?.load()
        }
    }

    func retryVideo(at index: Int) async {
        await playerPool.retry(index: index, videos: videos)
        playerGeneration += 1
    }

    func player(for index: Int) async -> AVPlayer? {
        await playerPool.player(for: index)
    }

    func onBackground() {
        Task { [playerPool] in
            await playerPool.pauseAll()
        }
    }

    func onForeground() {
        Task { [playerPool] in
            await playerPool.resumeCurrent()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: Self.muteKey)
        Task { [playerPool] in await playerPool.setMuted(muted) }
    }

    func socialState(for video: Video) -> FeedSocialState {
        socialStates[video.id] ?? Self.initialSocialState(for: video)
    }

    @discardableResult
    func toggleLike(for video: Video) -> Bool {
        updateSocialState(for: video) { state in
            state.isLiked.toggle()
            state.likeCount += state.isLiked ? 1 : -1
            state.likeCount = max(state.likeCount, 0)
        }.isLiked
    }

    @discardableResult
    func like(for video: Video) -> Bool {
        updateSocialState(for: video) { state in
            if !state.isLiked {
                state.likeCount += 1
            }
            state.isLiked = true
        }.isLiked
    }

    @discardableResult
    func toggleBookmark(for video: Video) -> Bool {
        updateSocialState(for: video) { state in
            state.isBookmarked.toggle()
            state.bookmarkCount += state.isBookmarked ? 1 : -1
            state.bookmarkCount = max(state.bookmarkCount, 0)
        }.isBookmarked
    }

    func recordShare(for video: Video) {
        updateSocialState(for: video) { state in
            state.shareCount += 1
        }
    }

    func addComment(_ text: String, for video: Video) {
        updateSocialState(for: video) { state in
            state.comments.insert(
                FeedComment(author: "You", text: text, colorIndex: 3,
                            likes: 0, timestamp: "Just now", replies: []),
                at: 0
            )
        }
    }

    @discardableResult
    func addReply(_ text: String, to commentID: UUID, for video: Video) -> Bool {
        var didAdd = false
        updateSocialState(for: video) { state in
            guard let index = state.comments.firstIndex(where: { $0.id == commentID }) else {
                return
            }

            state.comments[index].replies.append(
                CommentReply(
                    author: "You",
                    text: text,
                    colorIndex: 3,
                    likes: 0,
                    timestamp: "Just now"
                )
            )
            didAdd = true
        }
        return didAdd
    }

    @discardableResult
    func toggleCommentLike(_ commentID: UUID, for video: Video) -> Bool {
        var isLiked = false
        updateSocialState(for: video) { state in
            guard let index = state.comments.firstIndex(where: { $0.id == commentID }) else {
                return
            }

            state.comments[index].isLiked.toggle()
            state.comments[index].likes += state.comments[index].isLiked ? 1 : -1
            state.comments[index].likes = max(state.comments[index].likes, 0)
            isLiked = state.comments[index].isLiked
        }
        return isLiked
    }

    @discardableResult
    func toggleReplyLike(_ replyID: UUID, in commentID: UUID, for video: Video) -> Bool {
        var isLiked = false
        updateSocialState(for: video) { state in
            guard let commentIndex = state.comments.firstIndex(where: { $0.id == commentID }),
                  let replyIndex = state.comments[commentIndex].replies.firstIndex(where: { $0.id == replyID })
            else {
                return
            }

            state.comments[commentIndex].replies[replyIndex].isLiked.toggle()
            state.comments[commentIndex].replies[replyIndex].likes +=
                state.comments[commentIndex].replies[replyIndex].isLiked ? 1 : -1
            state.comments[commentIndex].replies[replyIndex].likes =
                max(state.comments[commentIndex].replies[replyIndex].likes, 0)
            isLiked = state.comments[commentIndex].replies[replyIndex].isLiked
        }
        return isLiked
    }

    func shouldShowGestureGuide(at index: Int) -> Bool {
        index == 0 && !hasSeenGestureGuide
    }

    func markGestureGuideSeen() {
        guard !hasSeenGestureGuide else { return }
        hasSeenGestureGuide = true
        UserDefaults.standard.set(true, forKey: Self.gestureGuideKey)
    }

    private func syncPool(to index: Int) {
        poolRevision += 1
        let revision = poolRevision
        let videos = videos

        poolTask?.cancel()
        poolTask = Task { [weak self, playerPool] in
            guard !Task.isCancelled else { return }

            await playerPool.advance(to: index, videos: videos)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }

                guard self.poolRevision == revision, self.currentIndex == index else {
                    self.syncPool(to: self.currentIndex)
                    return
                }

                self.playerGeneration += 1
                self.poolTask = nil
            }
        }
    }

    @discardableResult
    private func updateSocialState(
        for video: Video,
        mutate: (inout FeedSocialState) -> Void
    ) -> FeedSocialState {
        var state = socialState(for: video)
        mutate(&state)
        socialStates[video.id] = state
        persistSocialStates()
        return state
    }

    private func persistSocialStates() {
        guard let data = try? JSONEncoder().encode(socialStates) else { return }
        UserDefaults.standard.set(data, forKey: Self.socialStateKey)
    }

    private func refreshGeneratedCommentsIfNeeded(for videos: [Video]) {
        let storedVersion = UserDefaults.standard.integer(forKey: Self.commentCopyVersionKey)
        guard storedVersion < Self.currentCommentCopyVersion else { return }

        for video in videos {
            var state = socialStates[video.id] ?? Self.initialSocialState(for: video)
            let userThreads = state.comments.filter { comment in
                comment.author == "You" || comment.replies.contains { $0.author == "You" }
            }
            state.comments = userThreads + Self.initialComments(for: video)
            socialStates[video.id] = state
        }

        persistSocialStates()
        UserDefaults.standard.set(Self.currentCommentCopyVersion, forKey: Self.commentCopyVersionKey)
    }

    private static func loadSocialStates() -> [Int: FeedSocialState] {
        guard let data = UserDefaults.standard.data(forKey: socialStateKey),
              let decoded = try? JSONDecoder().decode([Int: FeedSocialState].self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private static func initialSocialState(for video: Video) -> FeedSocialState {
        FeedSocialState(
            likeCount: 240 + abs(video.id % 8_700),
            bookmarkCount: 90 + abs(video.id % 2_300),
            shareCount: 24 + abs(video.id % 960),
            comments: initialComments(for: video)
        )
    }

    private static func initialComments(for video: Video) -> [FeedComment] {
        let seed  = video.id
        let title = video.title
        let detailSource = video.description.isEmpty
            ? "the visual details in this clip"
            : video.description
        let detail = detailSource.count > 74
            ? "\(detailSource.prefix(71))..."
            : detailSource

        let mainPool: [(String, Int, [String])] = [
            ("Alex M.",   0, ["The mood in \(title) matches this perfectly.",
                              "That line about \(detail) is exactly what I noticed.",
                              "The first few seconds of \(title) pull you in so smoothly."]),
            ("Jordan K.", 1, ["The framing here makes \(title) feel intentional.",
                              "This is the kind of clip where the description actually fits.",
                              "The pacing is calm but still keeps moving."]),
            ("Maya R.",   2, ["I like how \(detail) comes through without needing extra text.",
                              "\(title) has such a clean visual rhythm.",
                              "The details feel simple, but very polished."]),
            ("Chris P.",  3, ["The color and motion are doing most of the storytelling here.",
                              "\(title) feels ready for a real short-form feed.",
                              "This one works because it stays focused on the subject."]),
            ("Taylor W.", 0, ["The description says \(detail), and the video really lands that idea.",
                              "Nothing feels random here; the shot has a clear point.",
                              "The loop potential on \(title) is strong."]),
            ("Sam L.",    1, ["This feels like the right clip to save and revisit.",
                              "The motion is smooth enough that I watched it twice.",
                              "\(title) is simple, but the execution carries it."]),
            ("Riley J.",  2, ["The subject is clear right away, which helps a lot.",
                              "The visual tone is consistent from start to finish.",
                              "This fits the feed better than a generic clip would."]),
            ("Jamie D.",  3, ["The title and description finally feel connected here.",
                              "The shot selection makes this feel more premium.",
                              "I would keep this style for the rest of the feed."]),
            ("Drew C.",   0, ["The detail in this one is what makes it work.",
                              "\(title) has a nice balance of motion and stillness.",
                              "This is clean enough to sit next to stronger reels."]),
            ("Casey B.",  1, ["The clip feels focused, not noisy.",
                              "That description is short, but it gives the video context.",
                              "The more I watch \(title), the more the small details stand out."]),
            ("Morgan A.", 2, ["This is a good example of title, caption, and video matching.",
                              "The visual story is clear without overexplaining it.",
                              "I like that the description does not fight the video."]),
            ("Avery N.",  3, ["The pacing makes the whole clip easier to watch.",
                              "\(title) feels natural in a vertical feed.",
                              "The best part is how simple the moment feels."]),
            ("Quinn S.",  0, ["This one feels calm but not boring.",
                              "The subject is easy to understand in the first second.",
                              "\(title) is the kind of clip that works well muted too."]),
            ("Reese T.",  1, ["The motion feels steady and easy to follow.",
                              "This has a stronger identity than the older generic comments.",
                              "The description gives just enough context for the clip."]),
        ]

        let replyPool: [(String, Int, String)] = [
            ("Jordan K.", 1, "yes, the title and shot finally match"),
            ("Maya R.",   2, "agreed, the visual tone is the best part"),
            ("Alex M.",   0, "the description makes the clip easier to read"),
            ("Sam L.",    1, "same, this feels much more intentional"),
            ("Riley J.",  2, "the pacing is what makes it work"),
            ("Chris P.",  3, "I noticed that detail too"),
            ("Taylor W.", 0, "this is exactly the kind of comment the clip needs"),
            ("Drew C.",   0, "the subject is clear right away"),
            ("Jamie D.",  3, "clean and focused is the right direction"),
            ("Avery N.",  3, "the caption helps without overdoing it"),
            ("Casey B.",  1, "this feels closer to a real feed now"),
            ("Quinn S.",  0, "yes, it makes the whole section feel connected"),
        ]

        let timestamps  = ["22m", "1h", "3h", "7h", "14h", "1d", "2d", "4d", "1w", "2w"]
        let count       = 9 + abs(seed % 6)
        var result: [FeedComment] = []

        for i in 0..<count {
            let row   = abs(seed &* 31 &+ i &* 7)  % mainPool.count
            let (author, colorIndex, lines) = mainPool[row]
            let line  = abs(seed &* 13 &+ i &* 5)  % lines.count
            let likes = abs(seed &* 17 &+ i &* 11) % 4_200
            let ts    = timestamps[abs(seed + i) % timestamps.count]

            var replies: [CommentReply] = []
            if abs(seed &+ i) % 5 < 2 {
                let rCount = 1 + abs(seed + i) % 3
                for j in 0..<rCount {
                    let rIdx   = abs(seed &* 7 &+ i &* 11 &+ j &* 3) % replyPool.count
                    let (rAuthor, rColor, rText) = replyPool[rIdx]
                    let rLikes = abs(seed &* 5 &+ i &* 7 &+ j)        % 480
                    let rTs    = timestamps[abs(seed + i + j + 1) % timestamps.count]
                    replies.append(CommentReply(author: rAuthor, text: rText,
                                                colorIndex: rColor, likes: rLikes, timestamp: rTs))
                }
            }

            result.append(FeedComment(author: author, text: lines[line],
                                      colorIndex: colorIndex, likes: likes,
                                      timestamp: ts, replies: replies))
        }
        return result
    }
}

extension FeedViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }
}

struct FeedSocialState: Codable, Equatable {
    var isLiked = false
    var isBookmarked = false
    var likeCount: Int
    var bookmarkCount: Int
    var shareCount: Int
    var comments: [FeedComment]
}

struct CommentReply: Codable, Equatable, Identifiable {
    let id: UUID
    var author: String
    var text: String
    var colorIndex: Int
    var likes: Int
    var isLiked: Bool
    var timestamp: String

    init(id: UUID = UUID(), author: String, text: String,
         colorIndex: Int, likes: Int = 0, isLiked: Bool = false, timestamp: String = "1d") {
        self.id = id; self.author = author; self.text = text
        self.colorIndex = colorIndex; self.likes = likes; self.isLiked = isLiked; self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        author     = try c.decode(String.self, forKey: .author)
        text       = try c.decode(String.self, forKey: .text)
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
        likes      = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        isLiked    = try c.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        timestamp  = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? "1d"
    }

    enum CodingKeys: String, CodingKey { case id, author, text, colorIndex, likes, isLiked, timestamp }

    var initials: String {
        let p = author.split(separator: " ")
        return String(p.prefix(2).compactMap { $0.first }).uppercased().isEmpty
            ? "?" : String(p.prefix(2).compactMap { $0.first }).uppercased()
    }
}

struct FeedComment: Codable, Equatable, Identifiable {
    let id: UUID
    var author: String
    var text: String
    var colorIndex: Int
    var likes: Int
    var isLiked: Bool
    var timestamp: String
    var replies: [CommentReply]

    init(id: UUID = UUID(), author: String, text: String, colorIndex: Int,
         likes: Int = 0, isLiked: Bool = false, timestamp: String = "1d", replies: [CommentReply] = []) {
        self.id = id; self.author = author; self.text = text
        self.colorIndex = colorIndex; self.likes = likes; self.isLiked = isLiked
        self.timestamp = timestamp; self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,    forKey: .id)
        author     = try c.decode(String.self,  forKey: .author)
        text       = try c.decode(String.self,  forKey: .text)
        colorIndex = try c.decode(Int.self,     forKey: .colorIndex)
        likes      = try c.decodeIfPresent(Int.self,           forKey: .likes)     ?? 0
        isLiked    = try c.decodeIfPresent(Bool.self,          forKey: .isLiked)   ?? false
        timestamp  = try c.decodeIfPresent(String.self,        forKey: .timestamp) ?? "1d"
        replies    = try c.decodeIfPresent([CommentReply].self, forKey: .replies)  ?? []
    }
    enum CodingKeys: String, CodingKey { case id, author, text, colorIndex, likes, isLiked, timestamp, replies }

    var initials: String {
        let pieces = author.split(separator: " ")
        let letters = pieces.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
