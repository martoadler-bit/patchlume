import SwiftUI

/// Bottom sheet to add a new node by category, ported from Modula's
/// `ModulePickerView` idea. Also hosts the starter-template browser.
struct NodeLibrarySheet: View {
    @EnvironmentObject var store: GraphStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Generators") {
                    ForEach(NodeCatalog.generatorTypes, id: \.self) { subtype in
                        row(kind: .generator, subtype: subtype)
                    }
                }
                Section("Modifiers") {
                    ForEach(NodeCatalog.modifierTypes, id: \.self) { subtype in
                        row(kind: .modifier, subtype: subtype)
                    }
                }
                Section("Combiners") {
                    ForEach(NodeCatalog.combinerTypes, id: \.self) { subtype in
                        row(kind: .combiner, subtype: subtype)
                    }
                }
                Section("Inputs") {
                    ForEach(NodeCatalog.inputTypes, id: \.self) { subtype in
                        row(kind: .input, subtype: subtype)
                    }
                }
                if !store.nodes.contains(where: { $0.kind == .output }) {
                    Section("Output") {
                        row(kind: .output, subtype: "output")
                    }
                }
            }
            .navigationTitle("Add Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func row(kind: NodeKind, subtype: String) -> some View {
        Button {
            store.addNode(kind: kind, subtype: subtype)
            dismiss()
        } label: {
            HStack {
                Circle().fill(NodeFamily.of(kind).color).frame(width: 8, height: 8)
                Text(NodeCatalog.displayName(kind: kind, subtype: subtype))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            }
            // Without this, the Spacer's expanded space has no hit target of
            // its own — tapping there lets the List row's built-in tap
            // highlight flash without the Button's action ever firing.
            // Every row below with a Spacer-pushed trailing element needs
            // this for the same reason.
            .contentShape(Rectangle())
        }
    }
}
