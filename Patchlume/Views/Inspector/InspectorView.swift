import SwiftUI

/// Parameter panel for the currently selected node — float sliders reuse
/// the same knob style as the canvas, plus int steppers, bool toggles, and
/// enum pickers for the other parameter types.
struct InspectorView: View {
    @EnvironmentObject var store: GraphStore
    let nodeID: UUID

    private var node: GraphNode? { store.node(nodeID) }
    private var parameters: [ParameterDescriptor] {
        guard let node else { return [] }
        return NodeCatalog.parameters(kind: node.kind, subtype: node.subtype)
    }

    var body: some View {
        if let node {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(NodeFamily.of(node.kind).color).frame(width: 8, height: 8)
                    Text(NodeCatalog.displayName(kind: node.kind, subtype: node.subtype))
                        .font(.headline)
                    Spacer()
                    Button {
                        store.selectedNodeID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }

                if parameters.isEmpty {
                    Text("This node has no adjustable parameters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(parameters) { parameter in
                        ParameterRow(
                            parameter: parameter,
                            value: node.parameters[parameter.id] ?? parameter.defaultValue,
                            onChange: { store.updateParameter(nodeID: node.id, paramID: parameter.id, value: $0) }
                        )
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}
