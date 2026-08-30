import SwiftUI

/// Flat "Node · Parameter" picker for adding one new target to a macro —
/// opened from the Macros panel so assigning a target and immediately
/// dialing in its range happens in the same place, no side trip to a
/// separate matrix required.
struct AddMacroTargetSheet: View {
    @EnvironmentObject var store: GraphStore
    @Environment(\.dismiss) private var dismiss
    let onAdd: (GraphNode, ParameterDescriptor) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.nodes) { node in
                    let params = NodeCatalog.parameters(kind: node.kind, subtype: node.subtype).filter { $0.type == .float }
                    if !params.isEmpty {
                        Section(NodeCatalog.displayName(kind: node.kind, subtype: node.subtype)) {
                            ForEach(params) { parameter in
                                Button {
                                    onAdd(node, parameter)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(parameter.label)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
