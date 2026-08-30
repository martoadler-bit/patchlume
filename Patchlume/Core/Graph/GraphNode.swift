import CoreGraphics
import Foundation

/// One node placed on the canvas. `subtype` selects which generator /
/// modifier / combiner / input the node actually runs (e.g. "plasma",
/// "blur", "bass") — the catalog is the single source of truth for what
/// parameters and ports a given (kind, subtype) pair exposes.
struct GraphNode: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: NodeKind
    var subtype: String
    var position: CGPoint
    /// paramID -> current value, for every parameter the catalog defines
    /// for this node's (kind, subtype).
    var parameters: [String: Float]
    /// paramID -> inline LFO, for whichever parameters have one attached
    /// (see `ParamModulator`). Most nodes have none; absent means "no
    /// modulation beyond its dialed-in value and any Macro assignments".
    var paramModulators: [String: ParamModulator]
    /// A stable filename (see `MediaStore`) for a "media" generator's
    /// picked photo or video — nil until the user actually picks one, and
    /// meaningless for every other node kind/subtype.
    var mediaRef: String?
    /// The string a "text" generator node displays — nil/empty falls back
    /// to a placeholder in `TextTextureEngine`. Meaningless for every other
    /// node kind/subtype, same convention as `mediaRef`.
    var textContent: String?

    init(id: UUID = UUID(), kind: NodeKind, subtype: String, position: CGPoint, parameters: [String: Float] = [:], paramModulators: [String: ParamModulator] = [:], mediaRef: String? = nil, textContent: String? = nil) {
        self.id = id
        self.kind = kind
        self.subtype = subtype
        self.position = position
        self.parameters = parameters
        self.paramModulators = paramModulators
        self.mediaRef = mediaRef
        self.textContent = textContent
    }
}
