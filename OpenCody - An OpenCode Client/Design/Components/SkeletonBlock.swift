//
//  SkeletonBlock.swift
//  OpenCody - An OpenCode Client
//

import SwiftUI

/// A shimmering placeholder bar — the building block of the app's loading skeletons.
///
/// Pass `width: nil` to fill the available width.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 4

    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.Colors.cloud.opacity(shimmer ? 0.10 : 0.04),
                        Theme.Colors.cloud.opacity(shimmer ? 0.04 : 0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
    }
}
