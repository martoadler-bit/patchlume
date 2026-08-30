import SwiftUI

/// The infinite-feeling node graph surface, ported from Modula's
/// `PatchCanvasView` (Module -> Node, Patch -> Graph). Pan with one finger
/// on empty space, pinch to zoom, drag a node by its header, drag a jack to
/// patch a cable.
struct GraphCanvasView: View {
    @EnvironmentObject var store: GraphStore
    @EnvironmentObject var lessonViewModel: LessonViewModel
    @StateObject private var canvasState = CanvasInteractionState()

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @GestureState private var panTranslation: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1.0

    private let canvasSize: CGFloat = 2400
    private let minScale: CGFloat = 0.1
    private let maxScale: CGFloat = 2.0

    var effectiveScale: CGFloat { (scale * pinchDelta).clamped(minScale, maxScale) }

    private var effectiveOffset: CGSize {
        let anchoredOffset = offset(forScale: scale * pinchDelta, keeping: offset, at: scale)
        return CGSize(
            width: anchoredOffset.width + panTranslation.width,
            height: anchoredOffset.height + panTranslation.height
        )
    }

    private func offset(forScale newScale: CGFloat, keeping baseOffset: CGSize, at baseScale: CGFloat) -> CGSize {
        guard viewportSize.width > 0, viewportSize.height > 0, baseScale > 0 else { return baseOffset }
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let contentPoint = CGPoint(
            x: (center.x - baseOffset.width) / baseScale,
            y: (center.y - baseOffset.height) / baseScale
        )
        return CGSize(
            width: center.x - contentPoint.x * newScale,
            height: center.y - contentPoint.y * newScale
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Fills the full viewport regardless of pan/zoom, so pan
                // always has something to grab — pan and pinch are combined
                // into one gesture scoped only to this background layer.
                Color(white: 0.07)
                    .contentShape(Rectangle())
                    .gesture(panGesture.simultaneously(with: pinchGesture))

                scaledContent
                CableLayerView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "canvas")
            .onPreferenceChange(PortAnchorsKey.self) { anchors in
                var resolved: [PortKey: CGPoint] = [:]
                for (key, anchor) in anchors {
                    resolved[key] = proxy[anchor]
                }
                canvasState.portPositions = resolved
            }
            .onAppear {
                viewportSize = proxy.size
                requestFit(viewport: proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                viewportSize = newSize
                requestFit(viewport: newSize)
            }
            .onChange(of: store.fitRequestToken) { _, _ in requestFit(viewport: proxy.size) }
            .onChange(of: lessonViewModel.activeLesson?.id) { _, _ in requestFit(viewport: proxy.size) }
            .onChange(of: lessonViewModel.focusNodeID) { _, newID in
                guard let newID else { return }
                DispatchQueue.main.async { focusOnNode(id: newID, viewport: proxy.size) }
            }
        }
        .clipped()
        .environmentObject(canvasState)
    }

    private var scaledContent: some View {
        ZStack(alignment: .topLeading) {
            backgroundGrid
            ForEach(store.nodes) { node in
                NodeContainerView(node: node, scale: effectiveScale)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .scaleEffect(effectiveScale, anchor: .topLeading)
        .offset(effectiveOffset)
    }

    private var backgroundGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 44
            var x: CGFloat = 0
            while x < size.width {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                }, with: .color(.white.opacity(0.05)))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                }, with: .color(.white.opacity(0.05)))
                y += step
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .allowsHitTesting(false)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("canvas"))
            .updating($panTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func requestFit(viewport: CGSize) {
        DispatchQueue.main.async {
            fitToContent(viewport: viewport)
        }
    }

    private func fitToContent(viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0, !store.nodes.isEmpty else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for node in store.nodes {
            let size = NodeLayoutMetrics.size(for: node.kind)
            minX = min(minX, node.position.x - size.width / 2)
            maxX = max(maxX, node.position.x + size.width / 2)
            minY = min(minY, node.position.y - size.height / 2)
            maxY = max(maxY, node.position.y + size.height / 2)
        }

        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        guard contentWidth > 0, contentHeight > 0 else { return }

        // The lesson speech bubble sits over the bottom of the screen —
        // while one's showing, fit against a shorter, top-anchored "usable"
        // viewport instead of the full one, so nodes never get auto-framed
        // underneath where the card covers them.
        let bottomReserved: CGFloat = lessonViewModel.activeLesson != nil ? 200 : 0
        let usableHeight = max(200, viewport.height - bottomReserved)

        let padding: CGFloat = 60
        let scaleToFitWidth = (viewport.width - padding * 2) / contentWidth
        let scaleToFitHeight = (usableHeight - padding * 2) / contentHeight
        let fitScale = min(scaleToFitWidth, scaleToFitHeight).clamped(minScale, maxScale)

        let contentCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        scale = fitScale
        offset = CGSize(
            width: viewport.width / 2 - contentCenter.x * fitScale,
            height: usableHeight / 2 - contentCenter.y * fitScale
        )
    }

    /// Pans/zooms so a single node (the one the current lesson/tour step is
    /// talking about) sits centered and comfortably readable — unlike
    /// `fitToContent`, this deliberately ignores every other node.
    private func focusOnNode(id: UUID, viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0, let node = store.node(id) else { return }

        let size = NodeLayoutMetrics.size(for: node.kind)
        let bottomReserved: CGFloat = lessonViewModel.activeLesson != nil ? 200 : 0
        let usableHeight = max(200, viewport.height - bottomReserved)

        let padding: CGFloat = 140
        let scaleToFitWidth = (viewport.width - padding * 2) / size.width
        let scaleToFitHeight = (usableHeight - padding * 2) / size.height
        let focusScale = min(scaleToFitWidth, scaleToFitHeight, 1.4).clamped(minScale, maxScale)

        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            scale = focusScale
            offset = CGSize(
                width: viewport.width / 2 - node.position.x * focusScale,
                height: usableHeight / 2 - node.position.y * focusScale
            )
        }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in state = value }
            .onEnded { value in
                let newScale = (scale * value).clamped(minScale, maxScale)
                offset = offset(forScale: newScale, keeping: offset, at: scale)
                scale = newScale
            }
    }
}
