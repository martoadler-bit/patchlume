import SwiftUI

/// Live performance panel — big sliders for every Macro, ridden by hand
/// while watching the preview. Presented at `.medium` detent with the
/// background still visible/interactive (see `ContentView`), so the live
/// Metal preview above the canvas stays on screen and touchable the whole
/// time, instead of a full-screen modal hiding it.
///
/// Also where a macro's targets are assigned and dialed in — right here,
/// not a separate trip to the matrix: tap "+ Add Target" to route a new
/// parameter, then adjust its Min/Max sweep (in that parameter's own real
/// units) with two sliders. Setting Min above Max inverts the sweep for
/// free — turning the macro up then moves the parameter down.
struct MacroControlPanelView: View {
    @EnvironmentObject var store: GraphStore
    @Environment(\.dismiss) private var dismiss
    @State private var newMacroName = ""
    @State private var showingAddMacro = false
    @State private var renamingMacro: Macro?
    @State private var renameText = ""
    @State private var addingTargetForMacro: Macro?

    var body: some View {
        NavigationStack {
            Group {
                if store.graph.macros.isEmpty {
                    ContentUnavailableView("No Macros Yet", systemImage: "slider.horizontal.3",
                        description: Text("Add a macro, then add a target right here to route it into a parameter."))
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(store.graph.macros) { macro in
                                macroCard(macro)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        newMacroName = "Macro \(store.graph.macros.count + 1)"
                        showingAddMacro = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Macro", isPresented: $showingAddMacro) {
                TextField("Name", text: $newMacroName)
                Button("Add") { store.addMacro(name: newMacroName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Macro", isPresented: Binding(get: { renamingMacro != nil }, set: { if !$0 { renamingMacro = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let macro = renamingMacro { store.renameMacro(id: macro.id, name: renameText) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $addingTargetForMacro) { macro in
                AddMacroTargetSheet { node, parameter in
                    // Full range by default — a broad, obviously-audible
                    // sweep to start from; narrow it with the sliders below.
                    store.setMacroAssignment(macroID: macro.id, nodeID: node.id, paramID: parameter.id,
                                              rangeMin: parameter.minValue, rangeMax: parameter.maxValue)
                }
                .environmentObject(store)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func macroCard(_ macro: Macro) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    renameText = macro.name
                    renamingMacro = macro
                } label: {
                    Text(macro.name).font(.headline).foregroundStyle(.primary)
                }
                Spacer()
                Text(String(format: "%.0f%%", macro.value * 100))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    store.removeMacro(id: macro.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
            }
            Slider(value: Binding(
                get: { macro.value },
                set: { store.updateMacroValue(id: macro.id, value: $0) }
            ), in: 0...1)
            .tint(.accentColor)

            let assignments = store.macroAssignments(for: macro.id)
            if !assignments.isEmpty {
                Divider()
                VStack(spacing: 12) {
                    ForEach(assignments) { assignment in
                        targetRow(macro: macro, assignment: assignment)
                    }
                }
            }

            Button {
                addingTargetForMacro = macro
            } label: {
                Label("Add Target", systemImage: "plus.circle")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func targetRow(macro: Macro, assignment: MacroAssignment) -> some View {
        if let node = store.node(assignment.nodeID),
           let parameter = NodeCatalog.parameters(kind: node.kind, subtype: node.subtype).first(where: { $0.id == assignment.paramID }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(NodeCatalog.displayName(kind: node.kind, subtype: node.subtype)) · \(parameter.label)")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    // Quick invert — swap Min/Max instead of dragging both
                    // sliders to their opposite ends by hand.
                    Button {
                        store.setMacroAssignment(macroID: macro.id, nodeID: node.id, paramID: parameter.id,
                                                  rangeMin: assignment.rangeMax, rangeMax: assignment.rangeMin)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        store.removeMacroAssignment(macroID: macro.id, nodeID: node.id, paramID: parameter.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                rangeSlider(label: "At 0%", value: assignment.rangeMin, parameter: parameter) { newMin in
                    store.setMacroAssignment(macroID: macro.id, nodeID: node.id, paramID: parameter.id,
                                              rangeMin: newMin, rangeMax: assignment.rangeMax)
                }
                rangeSlider(label: "At 100%", value: assignment.rangeMax, parameter: parameter) { newMax in
                    store.setMacroAssignment(macroID: macro.id, nodeID: node.id, paramID: parameter.id,
                                              rangeMin: assignment.rangeMin, rangeMax: newMax)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rangeSlider(label: String, value: Float, parameter: ParameterDescriptor, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: onChange), in: parameter.minValue...parameter.maxValue)
            Text(String(format: "%.2f", value)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
    }
}
