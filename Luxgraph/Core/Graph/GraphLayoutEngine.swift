import CoreGraphics
import Foundation

/// Port of Modula's `PatchLayoutEngine.nextFreePosition` — where to drop one
/// freshly-added node without disturbing anything already on the canvas.
/// Scans a generous grid of candidate slots, column by column, row by row,
/// and returns the first whose bounding box (plus a margin) doesn't overlap
/// any existing node.
enum GraphLayoutEngine {
    static func nextFreePosition(for kind: NodeKind, avoiding existing: [GraphNode], near preferredStart: CGPoint? = nil) -> CGPoint {
        let newSize = NodeLayoutMetrics.size(for: kind)
        let margin: CGFloat = 40
        let columnWidth: CGFloat = 260
        let rowHeight: CGFloat = 320
        let startX: CGFloat = preferredStart?.x ?? 160
        let startY: CGFloat = preferredStart?.y ?? 200
        let maxColumns = 10

        let existingRects: [CGRect] = existing.map { node in
            let size = NodeLayoutMetrics.size(for: node.kind)
            return CGRect(
                x: node.position.x - size.width / 2 - margin,
                y: node.position.y - size.height / 2 - margin,
                width: size.width + margin * 2,
                height: size.height + margin * 2
            )
        }

        var row = 0
        while row < 1_000 {
            for col in 0..<maxColumns {
                let candidate = CGPoint(x: startX + CGFloat(col) * columnWidth, y: startY + CGFloat(row) * rowHeight)
                let candidateRect = CGRect(
                    x: candidate.x - newSize.width / 2,
                    y: candidate.y - newSize.height / 2,
                    width: newSize.width,
                    height: newSize.height
                )
                if !existingRects.contains(where: { $0.intersects(candidateRect) }) {
                    return candidate
                }
            }
            row += 1
        }
        return CGPoint(x: startX, y: startY)
    }
}
