import SwiftUI

struct PageIndicatorView: View {
    let totalPages: Int
    @Binding var currentPage: Int
    let metrics: LaunchPadLayout.PageIndicatorMetrics
    let previewPage: Int?
    let previewProgress: CGFloat
    let settleProgress: CGFloat

    init(
        totalPages: Int,
        currentPage: Binding<Int>,
        metrics: LaunchPadLayout.PageIndicatorMetrics,
        previewPage: Int? = nil,
        previewProgress: CGFloat = 0,
        settleProgress: CGFloat = 0
    ) {
        self.totalPages = totalPages
        _currentPage = currentPage
        self.metrics = metrics
        self.previewPage = previewPage
        self.previewProgress = previewProgress
        self.settleProgress = settleProgress
    }

    var body: some View {
        let clampedPreviewProgress = min(max(previewProgress, 0), 1)
        let clampedSettleProgress = min(max(settleProgress, 0), 1)

        HStack(spacing: metrics.spacing) {
            ForEach(0..<totalPages, id: \.self) { page in
                Circle()
                    .fill(
                        Color.white.opacity(
                            opacity(
                                for: page,
                                previewProgress: clampedPreviewProgress,
                                settleProgress: clampedSettleProgress
                            )
                        )
                    )
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .scaleEffect(
                        scale(
                            for: page,
                            previewProgress: clampedPreviewProgress,
                            settleProgress: clampedSettleProgress
                        )
                    )
                    .animation(.easeInOut(duration: 0.16), value: currentPage)
                    .animation(LaunchPadMotion.pageEdgeIndicator, value: clampedPreviewProgress)
                    .animation(LaunchPadMotion.pageLanding, value: clampedSettleProgress)
                    .onTapGesture {
                        withAnimation(LaunchPadMotion.indicatorTap) {
                            currentPage = page
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }

    private func opacity(for page: Int, previewProgress: CGFloat, settleProgress: CGFloat) -> CGFloat {
        let isCurrent = page == currentPage
        let isPreview = page == previewPage

        var value: CGFloat = 0.32
        if isCurrent {
            value = previewPage == nil ? 0.95 : 0.95 - 0.32 * previewProgress
            value += 0.08 * settleProgress
        }
        if isPreview {
            value = max(value, 0.4 + 0.52 * previewProgress)
        }
        return min(value, 1)
    }

    private func scale(for page: Int, previewProgress: CGFloat, settleProgress: CGFloat) -> CGFloat {
        let isCurrent = page == currentPage
        let isPreview = page == previewPage

        var value: CGFloat = 0.92
        if isCurrent {
            value = previewPage == nil ? 1.05 : 1.05 - 0.08 * previewProgress
            value += 0.08 * settleProgress
        }
        if isPreview {
            value = max(value, 0.96 + 0.14 * previewProgress)
        }
        return value
    }
}
