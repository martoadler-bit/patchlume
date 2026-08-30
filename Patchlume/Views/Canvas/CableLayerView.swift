import SwiftUI

struct CableLayerView: View {
    @EnvironmentObject var canvasState: CanvasInteractionState
    @EnvironmentObject var store: GraphStore

    var body: some View {
        ZStack {
            if !store.cablesHidden {
                ForEach(store.connections) { connection in
                    connectionCable(connection)
                }
            }
            // The cable being actively dragged into place stays visible even
            // with Hide Cables on — you're mid-action on it, not decluttering
            // it away.
            if let pending = canvasState.pendingCable {
                pendingCable(pending)
            }
        }
    }

    // Purely decorative — no hit-testing. Disconnecting happens at the
    // port itself (long-press either jack, or "Disconnect All Cables" in a
    // node's menu), both proven-reliable touch targets.
    @ViewBuilder
    private func connectionCable(_ connection: GraphConnection) -> some View {
        let sourceKey = PortKey(nodeID: connection.sourceNodeID, portID: connection.sourcePortID, direction: .output)
        let destKey = PortKey(nodeID: connection.destNodeID, portID: connection.destPortID, direction: .input)
        if let start = canvasState.portPositions[sourceKey], let end = canvasState.portPositions[destKey] {
            let sag = max(abs(end.x - start.x) / 2, 60)
            let isSelected = touchesSelection(connection)
            CableShape(start: start, end: end, sag: sag)
                .stroke(portColor(for: connection.signalType), style: StrokeStyle(lineWidth: connection.signalType == .value ? 1.5 : 2, lineCap: .round, dash: connection.signalType == .value ? [4, 4] : []))
                .shadow(color: isSelected ? portColor(for: connection.signalType).opacity(0.5) : .clear, radius: isSelected ? 3 : 0)
                .allowsHitTesting(false)
                .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: sag)
                .opacity(opacity(for: connection))
        }
    }

    private func opacity(for connection: GraphConnection) -> Double {
        guard store.selectedNodeID != nil else { return connection.signalType == .value ? 0.35 : 0.5 }
        return touchesSelection(connection) ? 0.9 : 0.12
    }

    private func touchesSelection(_ connection: GraphConnection) -> Bool {
        guard let selectedNodeID = store.selectedNodeID else { return false }
        return connection.sourceNodeID == selectedNodeID || connection.destNodeID == selectedNodeID
    }

    @ViewBuilder
    private func pendingCable(_ pending: PendingCable) -> some View {
        if let originPoint = canvasState.portPositions[pending.origin] {
            let start = pending.origin.direction == .output ? originPoint : pending.currentPoint
            let end = pending.origin.direction == .output ? pending.currentPoint : originPoint
            CableShape(start: start, end: end, sag: max(abs(end.x - start.x) / 2, 60))
                .stroke(portColor(for: pending.signalType).opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 5]))
                .allowsHitTesting(false)
        }
    }
}
