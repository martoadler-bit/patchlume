import SwiftUI

/// Fullscreen live-preview overlay — tap anywhere (or the close button) to
/// return to the graph editor.
struct FullscreenPreviewView: View {
    let renderEngine: RenderEngine
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PreviewView(renderEngine: renderEngine)
                .ignoresSafeArea()
            // Same reason as the preview strip in ContentView: the Metal
            // view has touch interaction disabled, so the double-tap-to-
            // close gesture lives on a transparent SwiftUI layer above it
            // instead of directly on the (now non-interactive) Metal view.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(count: 2) { onClose() }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 4)
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
    }
}
