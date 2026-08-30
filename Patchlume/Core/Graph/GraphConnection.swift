import Foundation

/// A cable. Texture cables chain the render pipeline (generator -> modifier
/// -> combiner -> output); value cables patch an Input node's live value
/// into another node's single modulation-target parameter (see
/// `ParameterDescriptor.isPrimaryModulationTarget`).
struct GraphConnection: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceNodeID: UUID
    var sourcePortID: String
    var destNodeID: UUID
    var destPortID: String
    var signalType: SignalType

    init(id: UUID = UUID(), sourceNodeID: UUID, sourcePortID: String, destNodeID: UUID, destPortID: String, signalType: SignalType) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePortID = sourcePortID
        self.destNodeID = destNodeID
        self.destPortID = destPortID
        self.signalType = signalType
    }
}
