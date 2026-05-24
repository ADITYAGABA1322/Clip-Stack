//
//  LoadingErrorView.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import SwiftUI

struct LoadingErrorView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.yellow)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button(action: retryAction) {
                Label(retryTitle, systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(18)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    LoadingErrorView(
        title: "Clip unavailable",
        message: "The video could not be loaded.",
        retryTitle: "Retry",
        retryAction: {}
    )
    .padding()
    .background(.black)
}
