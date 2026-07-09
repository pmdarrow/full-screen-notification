import AppKit
import SwiftUI

struct TranslucentBlurBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()

            Color.black.opacity(0.42)

            LinearGradient(
                colors: [
                    .black.opacity(0.36),
                    .black.opacity(0.04),
                    .black.opacity(0.44),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        view.isEmphasized = true
    }
}
