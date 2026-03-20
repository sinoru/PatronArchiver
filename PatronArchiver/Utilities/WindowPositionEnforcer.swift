#if DEBUG
#if os(macOS)
import AppKit
import SwiftUI

struct WindowPositionEnforcer: NSViewRepresentable {
    func makeNSView(context: Context) -> EnforcerView {
        EnforcerView()
    }

    func updateNSView(_ nsView: EnforcerView, context: Context) {}
}

extension WindowPositionEnforcer {
    final class EnforcerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let screen = window.screen else { return }
            window.setFrameTopLeftPoint(
                NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY)
            )
        }
    }
}
#endif
#endif
