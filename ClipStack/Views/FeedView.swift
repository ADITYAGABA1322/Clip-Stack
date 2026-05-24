//
//  FeedView.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var currentIndex = 0
    @State private var scrollPosition: Int? = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.loadState {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)

            case .loaded:
                feedScrollView

            case .failed(let message):
                LoadingErrorView(
                    title: "Feed unavailable",
                    message: message,
                    retryTitle: "Try again",
                    retryAction: viewModel.retryCatalogLoad
                )
                .padding(24)
            }
        }
        .ignoresSafeArea()
        .task {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.onForeground()
            case .inactive, .background:
                viewModel.onBackground()
            @unknown default:
                break
            }
        }
        .preferredColorScheme(.dark)
    }

    private var feedScrollView: some View {
        let pageCount = viewModel.videos.count

        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.videos.enumerated()), id: \.offset) { index, video in
                    VideoPageView(
                        video: video,
                        index: index,
                        viewModel: viewModel
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            scrollPosition = currentIndex
        }
        .onChange(of: scrollPosition) { _, newValue in
            if let newValue {
                setCurrentIndex(newValue)
            }
        }
        .onScrollGeometryChange(for: Int?.self) { geometry in
            guard pageCount > 0, geometry.containerSize.height > 0 else {
                return nil
            }

            let rawIndex = (geometry.contentOffset.y / geometry.containerSize.height).rounded()
            let boundedIndex = min(max(Int(rawIndex), 0), pageCount - 1)
            return boundedIndex
        } action: { _, newValue in
            if let newValue {
                setCurrentIndex(newValue)
            }
        }
        .onScrollPhaseChange { _, newPhase, context in
            FeedPerformanceMonitor.scrollPhaseChanged(
                String(describing: newPhase),
                velocityY: context.velocity?.dy ?? 0
            )
        }
        .ignoresSafeArea()
    }

    private func setCurrentIndex(_ index: Int) {
        guard viewModel.videos.indices.contains(index), currentIndex != index else {
            return
        }

        currentIndex = index
        viewModel.onPageChanged(to: index)
    }
}

#Preview {
    FeedView()
}
