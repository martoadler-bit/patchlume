import SwiftUI

/// Patch-bay grid for the graph's actual cables: rows are every output
/// port in the graph, columns are every input port, tap an intersection to
/// connect. An input port takes exactly one cable (same rule the canvas
/// enforces), so selecting a cell clears any other filled cell in that
/// same column automatically. Cells where the source and destination
/// signal types don't match (or the row/column belong to the same node)
/// are dimmed and not tappable, same as the canvas refusing that cable.
struct ConnectionMatrixView: View {
    @EnvironmentObject var store: GraphStore
    @Environment(\.dismiss) private var dismiss

    private let rowHeight: CGFloat = 44
    private let headerHeight: CGFloat = 56
    private let labelColumnWidth: CGFloat = 96
    private let cellWidth: CGFloat = 48

    private struct PortRef: Identifiable {
        let id: String
        let node: GraphNode
        let port: PortDescriptor
    }

    private var rows: [PortRef] {
        store.nodes.flatMap { node in
            NodeCatalog.ports(kind: node.kind).outputs.map { PortRef(id: "\(node.id)-\($0.id)", node: node, port: $0) }
        }
    }

    private var columns: [PortRef] {
        store.nodes.flatMap { node in
            NodeCatalog.ports(kind: node.kind).inputs.map { PortRef(id: "\(node.id)-\($0.id)", node: node, port: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty || columns.isEmpty {
                    ContentUnavailableView("No Ports Yet", systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Add a few nodes first — this grid lists every port in the current graph."))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                Color.clear.frame(width: labelColumnWidth, height: headerHeight)
                                ForEach(rows) { row in
                                    VStack(spacing: 1) {
                                        Text(NodeCatalog.displayName(kind: row.node.kind, subtype: row.node.subtype))
                                            .font(.system(size: 11, weight: .medium))
                                        Text(row.port.label).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    .lineLimit(1)
                                    .frame(width: labelColumnWidth, height: rowHeight, alignment: .leading)
                                }
                            }
                            .background(Color(white: 0.12))

                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 0) {
                                    ForEach(columns) { column in
                                        VStack(spacing: 1) {
                                            Text(NodeCatalog.displayName(kind: column.node.kind, subtype: column.node.subtype))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                            Text(column.port.label).font(.system(size: 9, weight: .medium))
                                        }
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(width: cellWidth, height: headerHeight)
                                    }
                                }
                                ForEach(rows) { row in
                                    HStack(spacing: 0) {
                                        ForEach(columns) { column in
                                            cell(row: row, column: column)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connection Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(row: PortRef, column: PortRef) -> some View {
        let compatible = row.port.signalType == column.port.signalType && row.node.id != column.node.id
        let connected = store.connections.contains {
            $0.sourceNodeID == row.node.id && $0.sourcePortID == row.port.id &&
            $0.destNodeID == column.node.id && $0.destPortID == column.port.id
        }
        if compatible {
            Button {
                let destKey = PortKey(nodeID: column.node.id, portID: column.port.id, direction: .input)
                if connected {
                    store.disconnect(portKey: destKey)
                } else {
                    store.connect(source: PortKey(nodeID: row.node.id, portID: row.port.id, direction: .output), dest: destKey)
                }
            } label: {
                Rectangle()
                    .fill(connected ? portColor(for: row.port.signalType) : Color(white: 0.16))
                    .overlay(Rectangle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                    .overlay {
                        if connected {
                            Circle().fill(Color.white).frame(width: 8, height: 8)
                        }
                    }
                    .frame(width: cellWidth, height: rowHeight)
            }
            .buttonStyle(.plain)
        } else {
            Rectangle()
                .fill(Color(white: 0.08))
                .overlay(Rectangle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                .frame(width: cellWidth, height: rowHeight)
        }
    }
}
