import SwiftUI

/// Every patch saved to Documents/Patches (see `PatchStore`) — tap to
/// load, swipe to delete. Single Button per row, same reliable pattern
/// already proven for Templates/Node Library/Lessons/Challenges.
struct PatchBrowserView: View {
    @EnvironmentObject var viewModel: GraphViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var patches: [SavedPatch] = PatchStore.loadAll()

    var body: some View {
        NavigationStack {
            Group {
                if patches.isEmpty {
                    ContentUnavailableView("No Saved Patches", systemImage: "square.stack.3d.up.slash",
                        description: Text("Save your current graph from the \"...\" menu to see it here."))
                } else {
                    List {
                        ForEach(patches) { patch in
                            Button {
                                viewModel.loadSavedPatch(patch)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(patch.name).foregroundStyle(.primary)
                                    Text(patch.createdAt, style: .date)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    PatchStore.delete(patch)
                                    patches.removeAll { $0.id == patch.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Patches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
