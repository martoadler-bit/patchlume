import MetalKit
import SwiftUI

/// Thin `UIViewRepresentable` wrapper around an `MTKView` driven by
/// `RenderEngine`. This is the one piece of Patchlume that has no Modula
/// equivalent — the live Metal composite sitting alongside the patch canvas.
struct PreviewView: UIViewRepresentable {
    let renderEngine: RenderEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        // The SAME device RenderEngine's command queue/textures were built
        // with — see the comment on `RenderEngine.device` for why this
        // must not just call `MTLCreateSystemDefaultDevice()` again here.
        view.device = renderEngine.device
        view.delegate = renderEngine
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        // MTKView has touch interaction on by default even though nothing
        // here needs it directly — the tap-to-fullscreen gesture is
        // SwiftUI's own `.onTapGesture` on the view wrapping this one, not
        // anything MTKView itself handles. Left enabled, this continuously-
        // redrawing Metal-backed view can end up intercepting touches meant
        // for SwiftUI overlays that visually sit above it — notably the
        // top rows of the toolbar's "..." Menu, which drops down right over
        // the preview strip. Disabling it here removes the Metal view from
        // touch hit-testing entirely, leaving taps to the SwiftUI gesture
        // layer and anything presented above it.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
