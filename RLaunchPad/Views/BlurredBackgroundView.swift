import SwiftUI
import AppKit

struct BlurredBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .fullScreenUI
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct DarkOverlayView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.32), Color.black.opacity(0.56)],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.24)],
                center: .center,
                startRadius: 200,
                endRadius: 1100
            )
        }
        .ignoresSafeArea()
    }
}
