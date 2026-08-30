import SwiftUI

/// A real patch-bay grid: rows are Macros, columns are every modulatable
/// float parameter across the whole graph, and tapping a cell toggles that
/// route on/off (full rangeMin...rangeMax — fine-tuning the exact range or
/// inverting it lives in the Macros panel, right next to where a target
/// gets added). The macro-name column stays fixed while the parameter
/// columns scroll horizontally, since a graph can easily have more
/// parameter columns than fit on screen at once.
struct ModulationMatrixView: View {
    @EnvironmentObject var store: GraphStore
    @Environment(\.dismiss) private var dismiss

    private let rowHeight: CGFloat = 44
    private let headerHeight: CGFloat = 56
    private let labelColumnWidth: CGFloat = 96
    private let cellWidth: CGFloat = 48

    private struct Column: Identifiable {
        let id: String // "\(nodeID)-\(paramID)"
        let node: GraphNode
        let parameter: ParameterDescriptor
    }

    private var columns: [Column] {
        store.nodes.flatMap { node in
            NodeCatalog.parameters(kind: node.kind, subtype: node.subtype)
                .filter { $0.type == .float }
                .map { Column(id: "\(node.id)-\($0.id)", node: node, parameter: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.graph.macros.isEmpty {
                    ContentUnavailableView("No Macros Yet", systemImage: "square.grid.3x3",
                        description: Text("Add a macro from the Macros panel first, then wire it up here."))
                } else if columns.isEmpty {
                    ContentUnavailableView("No Parameters Yet", systemImage: "square.grid.3x3",
                        description: Text("Add a few nodes first — this grid lists every modulatable parameter in the graph."))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        HStack(alignment: .top, spacing: 0) {
                            // Fixed leading column: blank header cell, then
                            // one macro name per row.
                            VStack(spacing: 0) {
                                Color.clear.frame(width: labelColumnWidth, height: headerHeight)
                                ForEach(store.graph.macros) { macro in
                                    Text(macro.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                        .frame(width: labelColumnWidth, height: rowHeight, alignment: .leading)
                                }
                            }
                            .background(Color(white: 0.12))

                            // Scrolling parameter columns.
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(columns) { column in
                                        VStack(spacing: 1) {
                                            Text(NodeCatalog.displayName(kind: column.node.kind, subtype: column.node.subtype))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                            Text(column.parameter.label)
                                                .font(.system(size: 9, weight: .medium))
                                        }
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(width: cellWidth, height: headerHeight)
                                    }
                                }
                                ForEach(store.graph.macros) { macro in
                                    HStack(spacing: 0) {
                                        ForEach(columns) { column in
                                            cell(macro: macro, column: column)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Macro Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func cell(macro: Macro, column: Column) -> some View {
        let assigned = store.macroAssignment(macroID: macro.id, nodeID: column.node.id, paramID: column.parameter.id) != nil
        return Button {
            if assigned {
                store.removeMacroAssignment(macroID: macro.id, nodeID: column.node.id, paramID: column.parameter.id)
            } else {
                store.setMacroAssignment(macroID: macro.id, nodeID: column.node.id, paramID: column.parameter.id,
                                          rangeMin: column.parameter.minValue, rangeMax: column.parameter.maxValue)
            }
        } label: {
            Rectangle()
                .fill(assigned ? Color.accentColor : Color(white: 0.16))
                .overlay(Rectangle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                .overlay {
                    if assigned {
                        Circle().fill(Color.white).frame(width: 8, height: 8)
                    }
                }
                .frame(width: cellWidth, height: rowHeight)
        }
        .buttonStyle(.plain)
    }
}
