import CoreGraphics

/// Approximate on-screen footprint per node kind — used only for things
/// that need a size before a view has ever been rendered: laying out a
/// fresh graph without overlaps, and fitting the camera to the whole graph.
/// Mirrors Modula's `ModuleLayoutMetrics`.
enum NodeLayoutMetrics {
    static func size(for kind: NodeKind) -> CGSize {
        CGSize(width: width(for: kind), height: height(for: kind))
    }

    static func width(for kind: NodeKind) -> CGFloat {
        switch kind {
        case .combiner: return 200
        case .output: return 180
        default: return 196
        }
    }

    private static func height(for kind: NodeKind) -> CGFloat {
        switch kind {
        case .generator: return 300
        case .modifier: return 240
        case .combiner: return 220
        case .input: return 190
        case .output: return 170
        }
    }
}
