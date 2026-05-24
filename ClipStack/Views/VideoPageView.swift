//
//  VideoPageView.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct VideoPageView: View {
    let video: Video
    let index: Int
    let viewModel: FeedViewModel

    @State private var player: AVPlayer?
    @State private var playbackState: PlaybackState = .thumbnail
    @State private var statusObservation: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var timeObserverPlayer: AVPlayer?
    @State private var loopObserver: Any?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var scrubTime: Double = 0
    @State private var isScrubbing = false
    @State private var seekTarget: Double? = nil
    @State private var isPaused = false
    @State private var wasPlayingBeforeScrub = false
    @State private var lastLiveSeekTime: Double = -.infinity
    @State private var thumbDiameter: CGFloat = 10
    @State private var previewImage: UIImage? = nil
    @State private var imageGenerator: AVAssetImageGenerator? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var bufferingObservation: NSKeyValueObservation?
    @State private var isMidPlaybackBuffering = false
    @State private var showsPlaybackFeedback = false
    @State private var playbackFeedbackID = UUID()
    @State private var playbackRate: Float = 1
    @State private var feedbackIconName = "pause.fill"
    @State private var feedbackIconTint = Color.white
    @State private var showsControlPanel = false
    @State private var showsComments = false
    @State private var draftComment = ""
    @State private var expandedRepliesID: UUID? = nil
    @State private var replyTargetCommentID: UUID? = nil
    @State private var doubleTapLocation: CGPoint = .zero
    @State private var gestureGuideStep = 0
    @State private var gestureGuidePulse = false
    @State private var gestureGuideTask: Task<Void, Never>?
    @State private var showsReactionBurst = false
    @State private var reactionBurstIcon = "heart.fill"
    @State private var reactionBurstText = "Liked"
    @State private var reactionBurstColor = Color(red: 1, green: 0.27, blue: 0.37)
    @State private var reactionBurstID = UUID()
    @State private var reactionBurstPulse = false
    @State private var showsDoubleTapLike = false
    @State private var doubleTapLikeID = UUID()
    @State private var doubleTapLikePulse = false
    @State private var doubleTapLikeFade = false
    @State private var doubleTapLikeTravel = false
    @FocusState private var isCommentFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let safeB = geo.safeAreaInsets.bottom

            ZStack {
                Color.black

                thumbnailLayer
                    .opacity(playbackState == .playing ? 0 : 1)
                    .animation(.easeInOut(duration: 0.22), value: playbackState)

                if let player {
                    PlayerView(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(playbackState == .playing ? 1 : 0)
                        .animation(.easeInOut(duration: 0.22), value: playbackState)
                }

                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.35), .black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 280)
                }
                .allowsHitTesting(false)

                if (playbackState == .buffering && player == nil)
                    || (isMidPlaybackBuffering && !isPaused) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .transition(.opacity)
                }

                if case .failed(let message) = playbackState {
                    LoadingErrorView(
                        title: "Clip unavailable",
                        message: message,
                        retryTitle: "Retry",
                        retryAction: {
                            Task {
                                playbackState = .buffering
                                await viewModel.retryVideo(at: index)
                                await attachPlayer()
                            }
                        }
                    )
                    .padding(24)
                }

                fullScreenTapLayer

                VStack(spacing: 0) {
                    Spacer()

                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(video.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)

                            Text(video.description)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(3)
                                .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)

                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10, weight: .medium))
                                Text(video.formattedDuration)
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                            }
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)

                        VStack(spacing: 10) {
                            likeButton
                            commentsButton
                            bookmarkButton
                            shareButton
                            controlPanelButton
                            muteToggle
                        }
                        .frame(width: 72)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                    .padding(.bottom, 10)

                    progressBar(totalWidth: geo.size.width)
                        .padding(.bottom, safeB + 22)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                if showsControlPanel {
                    VStack {
                        Spacer()
                        quickControlsPanel(maxWidth: geo.size.width - 32)
                            .padding(.horizontal, 16)
                            .padding(.bottom, safeB + 66)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                gestureGuideOverlay
                reactionBurstFeedback
                doubleTapLikeFeedback(screenSize: geo.size, safeBottom: safeB)
                centerPlaybackFeedback
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .clipped()
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: showsControlPanel)
        .sheet(isPresented: $showsComments) {
            commentsSheet
        }
        .task(id: viewModel.playerGeneration) {
            await attachPlayer()
        }
        .onAppear {
            showGestureGuideIfNeeded()
        }
        .onDisappear {
            gestureGuideTask?.cancel()
            gestureGuideTask = nil
            removeObservers()
        }
    }

    // MARK: - Sub-views

    private var socialState: FeedSocialState {
        viewModel.socialState(for: video)
    }

    private var hasUserCommented: Bool {
        socialState.comments.contains { comment in
            comment.author == "You" || comment.replies.contains { $0.author == "You" }
        }
    }

    private var replyTargetComment: FeedComment? {
        guard let replyTargetCommentID else { return nil }
        return socialState.comments.first { $0.id == replyTargetCommentID }
    }

    private var commentPlaceholder: String {
        if let replyTargetComment {
            return "Reply to \(replyTargetComment.author)"
        }
        return "Add a comment..."
    }

    private var replyExpandAnimation: Animation {
        .smooth(duration: 0.28, extraBounce: 0)
    }

    private var thumbnailLayer: some View {
        AsyncImage(url: video.thumbnail) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Color.black.overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            case .empty:
                Color.black
            @unknown default:
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fullScreenTapLayer: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
                ExclusiveGesture(
                    SpatialTapGesture(count: 2),
                    SpatialTapGesture(count: 1)
                )
                .onEnded { value in
                    switch value {
                    case .first(let event):
                        doubleTapLocation = event.location
                        likeFromDoubleTap()
                    case .second:
                        handleSingleTap()
                    }
                }
            )
    }

    private var likeButton: some View {
        actionButton(
            icon: socialState.isLiked ? "heart.fill" : "heart",
            tint: socialState.isLiked ? Color(red: 1, green: 0.27, blue: 0.37) : .white,
            accessibilityLabel: socialState.isLiked ? "Unlike" : "Like",
            count: formattedCount(socialState.likeCount)
        ) {
            toggleLike()
        }
        .scaleEffect(socialState.isLiked ? 1.18 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: socialState.isLiked)
    }

    private var commentsButton: some View {
        actionButton(
            icon: hasUserCommented ? "message.fill" : "message",
            tint: .white,
            accessibilityLabel: "Comments",
            count: formattedCount(socialState.comments.count)
        ) {
            openComments()
        }
    }

    private var bookmarkButton: some View {
        actionButton(
            icon: socialState.isBookmarked ? "bookmark.fill" : "bookmark",
            tint: .white,
            accessibilityLabel: socialState.isBookmarked ? "Remove bookmark" : "Bookmark",
            count: formattedCount(socialState.bookmarkCount)
        ) {
            toggleBookmark()
        }
        .scaleEffect(socialState.isBookmarked ? 1.18 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: socialState.isBookmarked)
    }

    private var shareButton: some View {
        actionButton(
            icon: "paperplane.fill",
            tint: .white,
            accessibilityLabel: "Share",
            count: formattedCount(socialState.shareCount)
        ) {
            shareVideo()
        }
    }

    private var controlPanelButton: some View {
        actionButton(
            icon: showsControlPanel ? "xmark" : "speedometer",
            tint: .white,
            accessibilityLabel: showsControlPanel ? "Close playback controls" : "Playback controls"
        ) {
            hideGestureGuide()
            Haptics.selection()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                showsControlPanel.toggle()
            }
        }
    }

    private var muteToggle: some View {
        Button {
            toggleMute()
        } label: {
            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .clipStackLiquidGlassCircle()
                .frame(width: 68, height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isMuted ? "Unmute" : "Mute")
    }

    private func quickControlsPanel(maxWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            panelIconButton(icon: "gobackward.10", accessibilityLabel: "Back ten seconds") {
                skipLocally(by: -10)
            }

            ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { rate in
                let floatRate = Float(rate)
                Button {
                    setRate(floatRate)
                } label: {
                    Text(rateLabel(floatRate))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(playbackRate == floatRate ? .black : .white)
                        .frame(width: 42, height: 36)
                        .background(
                            playbackRate == floatRate ? .white : .white.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback speed \(rateLabel(floatRate))")
            }

            panelIconButton(icon: "goforward.10", accessibilityLabel: "Forward ten seconds") {
                skipLocally(by: 10)
            }
        }
        .padding(10)
        .frame(maxWidth: min(maxWidth, 360))
        .clipStackLiquidGlassRoundedRectangle(cornerRadius: 8)
    }

    private func panelIconButton(
        icon: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .clipStackLiquidGlassCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func actionButton(
        icon: String,
        tint: Color,
        accessibilityLabel: String,
        count: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 54, height: count == nil ? 52 : 40)
                    .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 2)

                if let count {
                    Text(count)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 1)
                }
            }
            .frame(width: 68, height: count == nil ? 58 : 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var commentsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(socialState.comments.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(socialState.comments) { comment in
                        commentRow(comment)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                        repliesBlock(for: comment, isExpanded: expandedRepliesID == comment.id)

                        Divider()
                            .opacity(0.1)
                            .padding(.leading, 54)
                    }
                }
                .padding(.bottom, 8)
            }
            .animation(replyExpandAnimation, value: expandedRepliesID)

            Divider().opacity(0.4)

            if let replyTargetComment {
                HStack(spacing: 8) {
                    Text("Replying to \(replyTargetComment.author)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Button {
                        clearReplyTarget()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .bottom))
                            .combined(with: .scale(scale: 0.98, anchor: .bottom)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.98, anchor: .bottom))
                    )
                )
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 0.18, green: 0.48, blue: 0.94))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text("Y")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }

                TextField(commentPlaceholder, text: $draftComment, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .focused($isCommentFieldFocused)

                Button {
                    addComment()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(
                            draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.4)
                                : Color(red: 0.18, green: 0.48, blue: 0.94)
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Post comment")
                .animation(.easeInOut(duration: 0.18), value: draftComment.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .animation(replyExpandAnimation, value: replyTargetCommentID)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func commentRow(_ comment: FeedComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(commentColor(for: comment))
                .frame(width: 36, height: 36)
                .overlay {
                    Text(comment.initials)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text(comment.timestamp)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }

                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                HStack(spacing: 16) {
                    Button {
                        startReply(to: comment)
                    } label: {
                        Text("Reply")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if !comment.replies.isEmpty {
                        Button {
                            toggleReplies(for: comment)
                        } label: {
                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(.secondary.opacity(0.4))
                                    .frame(width: 18, height: 1)

                                Text(expandedRepliesID == comment.id
                                     ? "Hide replies"
                                     : "View \(comment.replies.count) repl\(comment.replies.count == 1 ? "y" : "ies")")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }

            Button {
                toggleCommentLike(comment.id)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(comment.isLiked ? Color(red: 1, green: 0.27, blue: 0.37) : .secondary)
                        .scaleEffect(comment.isLiked ? 1.12 : 1)

                    Text(formattedCount(comment.likes))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(comment.isLiked ? "Unlike comment" : "Like comment")
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: comment.isLiked)
        }
    }

    @ViewBuilder
    private func repliesBlock(for comment: FeedComment, isExpanded: Bool) -> some View {
        if !comment.replies.isEmpty {
            let blockHeight: CGFloat? = isExpanded ? nil : 0

            VStack(spacing: 0) {
                ForEach(comment.replies) { reply in
                    replyRow(reply, parentID: comment.id)
                        .padding(.leading, 54)
                        .padding(.trailing, 16)
                        .padding(.vertical, 9)
                        .opacity(isExpanded ? 1 : 0)
                        .offset(y: isExpanded ? 0 : -6)
                        .scaleEffect(isExpanded ? 1 : 0.98, anchor: .top)
                }
            }
            .padding(.top, isExpanded ? 2 : 0)
            .padding(.bottom, isExpanded ? 4 : 0)
            .background(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(isExpanded ? 0.16 : 0))
                    .frame(width: 2)
                    .padding(.leading, 34)
                    .padding(.vertical, 10)
            }
            .frame(height: blockHeight, alignment: .top)
            .clipped()
            .opacity(isExpanded ? 1 : 0)
            .animation(replyExpandAnimation, value: isExpanded)
        }
    }

    @ViewBuilder
    private func replyRow(_ reply: CommentReply, parentID: UUID) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(replyColor(for: reply))
                .frame(width: 28, height: 28)
                .overlay {
                    Text(reply.initials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(reply.author)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text(reply.timestamp)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }

                Text(reply.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Button {
                toggleReplyLike(reply.id, in: parentID)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: reply.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(reply.isLiked ? Color(red: 1, green: 0.27, blue: 0.37) : .secondary)
                        .scaleEffect(reply.isLiked ? 1.12 : 1)

                    Text(formattedCount(reply.likes))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reply.isLiked ? "Unlike reply" : "Like reply")
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: reply.isLiked)
        }
    }

    private func replyColor(for reply: CommentReply) -> Color {
        switch reply.colorIndex % 4 {
        case 0:  Color(red: 0.92, green: 0.28, blue: 0.37)
        case 1:  Color(red: 0.13, green: 0.56, blue: 0.45)
        case 2:  Color(red: 0.49, green: 0.35, blue: 0.92)
        default: Color(red: 0.18, green: 0.48, blue: 0.94)
        }
    }

    private func progressBar(totalWidth: CGFloat) -> some View {
        let filled = max(totalWidth * progressFraction, 0)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(height: 3)

            Capsule()
                .fill(.white)
                .frame(width: filled, height: 3)
                .animation(isScrubbing ? .none : .linear(duration: 0.08), value: filled)

            Circle()
                .fill(.white)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .offset(x: max(filled - thumbDiameter / 2, 0))
                .animation(isScrubbing ? .none : .linear(duration: 0.08), value: filled)
        }
        .frame(width: totalWidth, height: 32)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbing {
                        isScrubbing = true
                        wasPlayingBeforeScrub = !isPaused
                        viewModel.setPaused(true, at: index)
                        lastLiveSeekTime = -.infinity
                        Haptics.lightImpact()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            thumbDiameter = 14
                        }
                    }
                    let t = clampedTime(for: value.location.x, width: totalWidth)
                    scrubTime = t
                    currentTime = t
                    if abs(t - lastLiveSeekTime) >= 0.12 {
                        lastLiveSeekTime = t
                        viewModel.liveSeek(to: t, at: index)
                        requestPreview(at: t)
                    }
                }
                .onEnded { value in
                    let t = clampedTime(for: value.location.x, width: totalWidth)
                    scrubTime = t
                    currentTime = t
                    seekTarget = t
                    isScrubbing = false
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        thumbDiameter = 10
                    }
                    previewTask?.cancel()
                    previewTask = nil
                    previewImage = nil
                    seek(to: t)
                    if wasPlayingBeforeScrub {
                        viewModel.setPaused(false, at: index)
                    }
                    Haptics.selection()
                }
        )
        .overlay(alignment: .top) {
            if isScrubbing {
                scrubPreviewWindow(filled: filled, totalWidth: totalWidth)
            }
        }
    }

    private func scrubPreviewWindow(filled: CGFloat, totalWidth: CGFloat) -> some View {
        let previewW: CGFloat = 80
        let previewH: CGFloat = 142
        let labelH:   CGFloat = 26
        let gap:      CGFloat = 10

        let thumbCenterX = max(filled, thumbDiameter / 2)
        let clampedX = min(max(thumbCenterX, previewW / 2), totalWidth - previewW / 2)
        let xOffset = clampedX - totalWidth / 2
        let yOffset = -(previewH + 6 + labelH + gap)

        return VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black)

                if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                }
            }
            .frame(width: previewW, height: previewH)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 4)

            Text(formattedTime(displayedTime))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .clipStackLiquidGlassCapsule()
        }
        .offset(x: xOffset, y: yOffset)
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isScrubbing)
    }

    private var centerPlaybackFeedback: some View {
        Image(systemName: feedbackIconName)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(feedbackIconTint)
            .frame(width: 76, height: 76)
            .clipStackLiquidGlassCircle()
            .scaleEffect(showsPlaybackFeedback ? 1 : 0.8)
            .opacity(showsPlaybackFeedback ? 1 : 0)
            .contentTransition(.symbolEffect(.replace))
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
            .allowsHitTesting(false)
    }

    private func liquidFeedbackIcon(
        icon: String,
        tint: Color,
        glow: Color,
        isPulsed: Bool,
        size: CGFloat,
        iconSize: CGFloat
    ) -> some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .clipStackLiquidGlassCircle(tint: glow)
            .shadow(color: glow.opacity(isPulsed ? 0.38 : 0.18), radius: isPulsed ? 24 : 12, x: 0, y: 10)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        .scaleEffect(isPulsed ? 1 : 0.78)
        .opacity(isPulsed ? 1 : 0.92)
    }

    private var gestureGuideOverlay: some View {
        Group {
            if gestureGuideStep > 0 {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.08))
                            .frame(width: 84, height: 84)

                        if gestureGuideStep == 1 {
                            swipeGuideIcon
                        } else {
                            doubleTapGuideIcon
                        }
                    }

                    VStack(spacing: 5) {
                        Text(gestureGuideStep == 1 ? "Swipe up for next" : "Double tap to like")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(gestureGuideStep == 1
                             ? "Explore more clips"
                             : "Show some love ❤️")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    HStack(spacing: 6) {
                        ForEach(1...2, id: \.self) { step in
                            Capsule()
                                .fill(gestureGuideStep == step
                                      ? Color.white
                                      : Color.white.opacity(0.28))
                                .frame(width: gestureGuideStep == step ? 18 : 6, height: 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: gestureGuideStep)
                        }
                    }
                }
                .id(gestureGuideStep)
                .padding(.vertical, 28)
                .padding(.horizontal, 32)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.black.opacity(0.38))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.45), radius: 32, x: 0, y: 14)
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -44)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var swipeGuideIcon: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 46, weight: .semibold))
            .foregroundStyle(.white)
            .symbolEffect(.bounce.up.byLayer, options: .repeating, isActive: gestureGuideStep == 1)
            .shadow(color: .black.opacity(0.22), radius: 10)
    }

    @ViewBuilder private var doubleTapGuideIcon: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.37))
            .symbolEffect(.pulse.wholeSymbol, options: .repeating, isActive: gestureGuideStep == 2)
            .shadow(color: Color(red: 1, green: 0.27, blue: 0.37).opacity(0.4), radius: 16)
    }

    private var reactionBurstFeedback: some View {
        Group {
            if showsReactionBurst {
                VStack(spacing: 8) {
                    liquidFeedbackIcon(
                        icon: reactionBurstIcon,
                        tint: reactionBurstColor,
                        glow: reactionBurstColor,
                        isPulsed: reactionBurstPulse,
                        size: 82,
                        iconSize: 31
                    )

                    if !reactionBurstText.isEmpty {
                        Text(reactionBurstText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .clipStackLiquidGlassCapsule()
                    }
                }
                .shadow(color: .black.opacity(0.42), radius: 20, x: 0, y: 10)
                .scaleEffect(reactionBurstPulse ? 1 : 0.84)
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -52)
        .allowsHitTesting(false)
    }

    private func doubleTapLikeFeedback(screenSize: CGSize, safeBottom: CGFloat) -> some View {
        Group {
            if showsDoubleTapLike {
                let targetPoint = doubleTapLikeTravel
                    ? likeRailTarget(in: screenSize, safeBottom: safeBottom)
                    : doubleTapLocation

                Image(systemName: "heart.fill")
                    .font(.system(size: 88, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.22, blue: 0.35))
                    .shadow(color: Color(red: 1, green: 0.22, blue: 0.35).opacity(0.6), radius: 28)
                    .shadow(color: Color(red: 1, green: 0.22, blue: 0.35).opacity(0.28), radius: 56)
                    .scaleEffect(doubleTapLikeScale)
                    .opacity(doubleTapLikeFade ? 0 : 1)
                    .position(x: targetPoint.x, y: targetPoint.y)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
    }

    private var doubleTapLikeScale: CGFloat {
        guard doubleTapLikePulse else { return 0.1 }
        return doubleTapLikeTravel ? 0.22 : 1
    }

    private func likeRailTarget(in screenSize: CGSize, safeBottom: CGFloat) -> CGPoint {
        let actionStackHeight: CGFloat = (64.0 * 4.0) + (58.0 * 2.0) + (10.0 * 5.0)
        let actionStackBottom = screenSize.height - (32 + safeBottom + 22) - 10
        let likeButtonCenterY = actionStackBottom - actionStackHeight + 38
        return CGPoint(x: screenSize.width - 40, y: max(112, likeButtonCenterY))
    }

    // MARK: - Playback helpers

    private var displayedTime: Double {
        let t = isScrubbing ? scrubTime : (seekTarget ?? currentTime)
        return min(max(t, 0), max(duration, 1))
    }

    private var progressFraction: Double {
        displayedTime / max(duration, 1)
    }

    private func handleSingleTap() {
        hideGestureGuide()

        guard !showsControlPanel else {
            Haptics.selection()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                showsControlPanel = false
            }
            return
        }

        togglePlayback(showFeedback: true)
    }

    private func togglePlayback(showFeedback: Bool = false) {
        let next = !isPaused
        isPaused = next
        viewModel.setPaused(next, at: index)
        Haptics.lightImpact()
        if showFeedback {
            flashFeedback(icon: next ? "play.fill" : "pause.fill")
        }
    }

    private func toggleLike() {
        hideGestureGuide()
        Haptics.mediumImpact()
        let isNowLiked = viewModel.toggleLike(for: video)
        if isNowLiked {
            flashReaction(
                icon: "heart.fill",
                text: "",
                color: Color(red: 1, green: 0.27, blue: 0.37)
            )
        }
    }

    private func likeFromDoubleTap() {
        hideGestureGuide()
        Haptics.mediumImpact()
        flashDoubleTapLike()
    }

    private func openComments() {
        hideGestureGuide()
        Haptics.selection()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            showsControlPanel = false
        }
        showsComments = true
    }

    private func addComment() {
        let text = draftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let replyTargetCommentID {
            let didAdd = viewModel.addReply(text, to: replyTargetCommentID, for: video)
            if didAdd {
                withAnimation(replyExpandAnimation) {
                    expandedRepliesID = replyTargetCommentID
                }
            }
        } else {
            viewModel.addComment(text, for: video)
        }

        draftComment = ""
        clearReplyTarget()
        isCommentFieldFocused = false
        Haptics.selection()
    }

    private func toggleReplies(for comment: FeedComment) {
        Haptics.selection()
        withAnimation(replyExpandAnimation) {
            expandedRepliesID = expandedRepliesID == comment.id ? nil : comment.id
        }
    }

    private func startReply(to comment: FeedComment) {
        Haptics.selection()
        withAnimation(replyExpandAnimation) {
            replyTargetCommentID = comment.id
            expandedRepliesID = comment.id
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            isCommentFieldFocused = true
        }
    }

    private func clearReplyTarget() {
        withAnimation(replyExpandAnimation) {
            replyTargetCommentID = nil
        }
    }

    private func toggleCommentLike(_ commentID: UUID) {
        Haptics.lightImpact()
        viewModel.toggleCommentLike(commentID, for: video)
    }

    private func toggleReplyLike(_ replyID: UUID, in commentID: UUID) {
        Haptics.lightImpact()
        viewModel.toggleReplyLike(replyID, in: commentID, for: video)
    }

    private func toggleBookmark() {
        hideGestureGuide()
        Haptics.selection()
        let isNowBookmarked = viewModel.toggleBookmark(for: video)
        flashFeedback(
            icon: isNowBookmarked ? "bookmark.fill" : "bookmark",
            tint: .white
        )
    }

    private func toggleMute() {
        hideGestureGuide()
        let next = !viewModel.isMuted
        Haptics.selection()
        viewModel.setMuted(next)
        flashFeedback(icon: next ? "speaker.slash.fill" : "speaker.wave.2.fill")
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        Haptics.selection()
        viewModel.setPlaybackRate(rate, at: index)
        flashFeedback(icon: "speedometer")
    }

    private func skipLocally(by seconds: Double) {
        let target = min(max(displayedTime + seconds, 0), max(duration, 1))
        Haptics.mediumImpact()
        seekTarget = target
        currentTime = target
        seek(to: target)
        flashFeedback(icon: seconds < 0 ? "gobackward.10" : "goforward.10")
    }

    private func seek(to seconds: Double) {
        currentTime = seconds
        viewModel.seek(to: seconds, at: index)
    }

    private func shareVideo() {
        hideGestureGuide()
        Haptics.selection()

        let av = UIActivityViewController(activityItems: [video.title, video.url], applicationActivities: nil)
        av.setValue(video.title, forKey: "subject")
        av.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in
                viewModel.recordShare(for: video)
                Haptics.mediumImpact()
                flashReaction(icon: "paperplane.fill", text: "Shared", color: .white)
            }
        }
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow?.rootViewController
        else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(av, animated: true)
    }

    private func clampedTime(for x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(x / max(width, 1), 0), 1)
        return Double(fraction) * max(duration, 1)
    }

    private func rateLabel(_ rate: Float) -> String {
        switch rate {
        case 0.75:
            "0.75x"
        case 1:
            "1x"
        case 1.25:
            "1.25x"
        case 1.5:
            "1.5x"
        case 2:
            "2x"
        default:
            "\(rate)x"
        }
    }

    private func showGestureGuideIfNeeded() {
        guard viewModel.shouldShowGestureGuide(at: index), gestureGuideStep == 0 else { return }

        viewModel.markGestureGuideSeen()
        gestureGuideTask?.cancel()
        gestureGuideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            gestureGuidePulse = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                gestureGuideStep = 1
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55).repeatCount(2, autoreverses: true)) {
                gestureGuidePulse = true
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }

            gestureGuidePulse = false
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                gestureGuideStep = 2
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.42).repeatCount(2, autoreverses: true)) {
                gestureGuidePulse = true
            }

            try? await Task.sleep(nanoseconds: 1_350_000_000)
            guard !Task.isCancelled else { return }

            gestureGuideTask = nil
            withAnimation(.easeOut(duration: 0.18)) {
                gestureGuideStep = 0
                gestureGuidePulse = false
            }
        }
    }

    private func hideGestureGuide() {
        guard gestureGuideStep != 0 else { return }
        gestureGuideTask?.cancel()
        gestureGuideTask = nil
        withAnimation(.easeOut(duration: 0.18)) {
            gestureGuideStep = 0
            gestureGuidePulse = false
        }
    }

    private func flashReaction(icon: String, text: String, color: Color) {
        let id = UUID()
        reactionBurstIcon = icon
        reactionBurstText = text
        reactionBurstColor = color
        reactionBurstID = id
        reactionBurstPulse = false

        withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
            showsReactionBurst = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 35_000_000)
            guard reactionBurstID == id else { return }
            withAnimation(.easeOut(duration: 0.62)) {
                reactionBurstPulse = true
            }

            try? await Task.sleep(nanoseconds: 720_000_000)
            guard reactionBurstID == id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showsReactionBurst = false
                reactionBurstPulse = false
            }
        }
    }

    private func commentColor(for comment: FeedComment) -> Color {
        switch comment.colorIndex % 4 {
        case 0:
            Color(red: 0.92, green: 0.28, blue: 0.37)
        case 1:
            Color(red: 0.13, green: 0.56, blue: 0.45)
        case 2:
            Color(red: 0.49, green: 0.35, blue: 0.92)
        default:
            Color(red: 0.18, green: 0.48, blue: 0.94)
        }
    }

    private func formattedCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            String(format: "%.1fM", Double(count) / 1_000_000)
        case 10_000...:
            "\(count / 1_000)K"
        case 1_000...:
            String(format: "%.1fK", Double(count) / 1_000)
        default:
            "\(count)"
        }
    }

    private func flashFeedback(icon: String, tint: Color = .white) {
        let id = UUID()
        feedbackIconName = icon
        feedbackIconTint = tint
        playbackFeedbackID = id
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.08)) {
            showsPlaybackFeedback = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard playbackFeedbackID == id else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                showsPlaybackFeedback = false
            }
        }
    }

    private func flashDoubleTapLike() {
        let id = UUID()
        doubleTapLikeID = id
        doubleTapLikePulse = false
        doubleTapLikeFade = false
        doubleTapLikeTravel = false

        withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) {
            showsDoubleTapLike = true
            doubleTapLikePulse = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard doubleTapLikeID == id else { return }

            withAnimation(.easeInOut(duration: 0.34)) {
                doubleTapLikeTravel = true
            }

            try? await Task.sleep(nanoseconds: 260_000_000)
            guard doubleTapLikeID == id else { return }
            viewModel.like(for: video)
            Haptics.lightImpact()

            try? await Task.sleep(nanoseconds: 70_000_000)
            guard doubleTapLikeID == id else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                doubleTapLikeFade = true
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard doubleTapLikeID == id else { return }
            showsDoubleTapLike = false
            doubleTapLikePulse = false
            doubleTapLikeFade = false
            doubleTapLikeTravel = false
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds.rounded(.down)), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Player attachment

    @MainActor
    private func attachPlayer() async {
        statusObservation?.invalidate()
        statusObservation = nil

        guard let assignedPlayer = await viewModel.player(for: index) else {
            removeTimeObserver()
            removeLoopObserver()
            player = nil
            playbackState = .thumbnail
            return
        }

        player = assignedPlayer

        guard let item = assignedPlayer.currentItem else {
            removeTimeObserver()
            removeLoopObserver()
            playbackState = .thumbnail
            return
        }

        if viewModel.currentIndex == index {
            FeedPerformanceMonitor.firstFrameRequested(index: index, videoID: video.id)
        }

        observeStatus(of: item)
        observeProgress(on: assignedPlayer)
        observeLoop(on: assignedPlayer, item: item)
        observeBufferingStatus(on: assignedPlayer)
        setupImageGenerator(for: item.asset)
    }

    @MainActor
    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { observedItem, _ in
            Task { @MainActor in
                switch observedItem.status {
                case .unknown:
                    if playbackState != .playing {
                        playbackState = .thumbnail
                    }
                case .readyToPlay:
                    FeedPerformanceMonitor.firstFrameReady(index: index, videoID: video.id)
                    playbackState = .playing
                case .failed:
                    let message = observedItem.error?.localizedDescription ?? "The video could not be loaded."
                    FeedPerformanceMonitor.firstFrameFailed(index: index, videoID: video.id, message: message)
                    playbackState = .failed(message)
                @unknown default:
                    let message = "The video entered an unknown playback state."
                    FeedPerformanceMonitor.firstFrameFailed(index: index, videoID: video.id, message: message)
                    playbackState = .failed(message)
                }
            }
        }
    }

    private func observeProgress(on player: AVPlayer) {
        removeTimeObserver()
        duration = Double(video.duration)

        let t = player.currentTime().seconds
        if t.isFinite {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { currentTime = t }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            let s = time.seconds
            guard s.isFinite else { return }

            if let target = seekTarget {
                if abs(s - target) < 1.0 {
                    seekTarget = nil
                    currentTime = s
                }
            } else {
                currentTime = s
            }

            let d = player.currentItem?.duration.seconds
            if let d, d.isFinite, d > 0 { duration = d }
        }
    }

    private func observeLoop(on player: AVPlayer, item: AVPlayerItem) {
        removeLoopObserver()
        let p = player
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero) { completed in
                guard completed else { return }
                p.play()
            }
            DispatchQueue.main.async { seekTarget = nil; currentTime = 0 }
        }
    }

    // MARK: - Mid-playback buffering

    private func observeBufferingStatus(on player: AVPlayer) {
        bufferingObservation?.invalidate()
        bufferingObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { p, _ in
            Task { @MainActor [weak p] in
                guard let p else { return }
                isMidPlaybackBuffering = (p.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
    }

    // MARK: - Scrub preview

    private func setupImageGenerator(for asset: AVAsset) {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 80, height: 142)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 1.0, preferredTimescale: 600)
        imageGenerator = gen
    }

    private func requestPreview(at seconds: Double) {
        guard let gen = imageGenerator else { return }
        previewTask?.cancel()
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        previewTask = Task.detached(priority: .userInitiated) {
            do {
                let (cgImage, _) = try await gen.image(at: time)
                guard !Task.isCancelled else { return }
                let uiImage = UIImage(cgImage: cgImage)
                await MainActor.run { previewImage = uiImage }
            } catch {
            }
        }
    }

    // MARK: - Cleanup

    private func removeObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferingObservation?.invalidate()
        bufferingObservation = nil
        isMidPlaybackBuffering = false
        removeTimeObserver()
        removeLoopObserver()
        previewTask?.cancel()
        previewTask = nil
        imageGenerator = nil
        previewImage = nil
    }

    private func removeTimeObserver() {
        if let timeObserver { timeObserverPlayer?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    private func removeLoopObserver() {
        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer) }
        loopObserver = nil
    }
}

private enum PlaybackState: Equatable {
    case thumbnail
    case buffering
    case playing
    case failed(String)
}

private extension View {
    @ViewBuilder
    func clipStackLiquidGlassCircle(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint?.opacity(0.18)).interactive(true), in: Circle())
        } else {
            background {
                Circle()
                    .fill(.ultraThinMaterial)
                if let tint {
                    Circle()
                        .fill(tint.opacity(0.12))
                }
            }
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.16), lineWidth: 0.6)
                )
        }
    }

    @ViewBuilder
    func clipStackLiquidGlassCapsule(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint?.opacity(0.16)).interactive(true), in: Capsule())
        } else {
            background {
                Capsule()
                    .fill(.ultraThinMaterial)
                if let tint {
                    Capsule()
                        .fill(tint.opacity(0.1))
                }
            }
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    func clipStackLiquidGlassRoundedRectangle(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint?.opacity(0.14)).interactive(true), in: shape)
        } else {
            background {
                shape
                    .fill(.ultraThinMaterial)
                if let tint {
                    shape
                        .fill(tint.opacity(0.08))
                }
            }
                .overlay(
                    shape
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                )
        }
    }
}
