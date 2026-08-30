import CoreGraphics
import SwiftUI

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), hi)
    }
}

extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(self, lo), hi)
    }
}

/// The five node kinds of a Patchlume patch, mirroring Modula's ModuleKind
/// family idea but for visual signal instead of audio signal.
enum NodeKind: String, Codable, CaseIterable {
    case generator, modifier, combiner, input, output
}

/// Broad visual family used only for the accent color on a node card —
/// same "family, not per-type" color idea as Modula's ModuleFamily, so a
/// busy graph reads at a glance instead of as 20 unrelated colors.
enum NodeFamily {
    case generator, modifier, combiner, input, output

    var color: Color {
        switch self {
        case .generator: return .cyan
        case .modifier: return .orange
        case .combiner: return .purple
        case .input: return .green
        case .output: return .pink
        }
    }

    static func of(_ kind: NodeKind) -> NodeFamily {
        switch kind {
        case .generator: return .generator
        case .modifier: return .modifier
        case .combiner: return .combiner
        case .input: return .input
        case .output: return .output
        }
    }
}

enum SignalType: Hashable, Codable {
    case texture
    case value
}

func portColor(for signalType: SignalType) -> Color {
    switch signalType {
    case .texture: return .cyan
    case .value: return .yellow
    }
}

enum ParamType: String, Codable {
    case float, int, bool, enumType, color
}

struct ParameterDescriptor: Identifiable, Hashable {
    let id: String
    let label: String
    let type: ParamType
    let minValue: Float
    let maxValue: Float
    let defaultValue: Float
    var unit: String = ""
    /// Only used when type == .enumType — display names for successive
    /// integer values 0...(options.count-1).
    var options: [String] = []
    /// If true, this is the parameter an Input node's cable lands on when
    /// dropped on this node's single modulation ("mod") port.
    var isPrimaryModulationTarget: Bool = false

    func normalized(_ value: Float) -> Float {
        guard maxValue > minValue else { return 0 }
        return ((value - minValue) / (maxValue - minValue)).clamped(0, 1)
    }
}

enum PortDirection: Hashable {
    case input, output
}

struct PortDescriptor: Identifiable, Hashable {
    let id: String
    let label: String
    let signalType: SignalType
}

struct PortKey: Hashable {
    let nodeID: UUID
    let portID: String
    let direction: PortDirection
}

/// Collects the on-screen center of every port jack, in the canvas's own
/// coordinate space, so cables can be drawn and drop targets hit-tested
/// without each port view needing to know about any other.
struct PortAnchorsKey: PreferenceKey {
    static var defaultValue: [PortKey: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [PortKey: Anchor<CGPoint>], nextValue: () -> [PortKey: Anchor<CGPoint>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct PendingCable {
    let origin: PortKey
    let signalType: SignalType
    var currentPoint: CGPoint
}

/// Shared drag-to-connect state for the whole canvas. Lives above the
/// per-node views so any `PortView`, anywhere in the tree, can start or
/// finish a cable without a chain of callback parameters.
final class CanvasInteractionState: ObservableObject {
    @Published var pendingCable: PendingCable?
    @Published var portPositions: [PortKey: CGPoint] = [:]

    func nearestPort(to point: CGPoint, excluding origin: PortKey, maxDistance: CGFloat = 44) -> PortKey? {
        var best: (key: PortKey, distance: CGFloat)?
        for (key, position) in portPositions {
            guard key != origin, key.direction != origin.direction else { continue }
            let dx = position.x - point.x
            let dy = position.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance <= maxDistance else { continue }
            if best == nil || distance < best!.distance {
                best = (key, distance)
            }
        }
        return best?.key
    }
}
