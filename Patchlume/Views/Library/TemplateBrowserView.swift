import SwiftUI

/// Starter templates — a generator plus a short modifier chain, with an
/// input pre-wired into the generator's reactivity parameter.
struct TemplateBrowserView: View {
    @EnvironmentObject var viewModel: GraphViewModel
    @EnvironmentObject var lessonViewModel: LessonViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(GraphTemplateCatalog.categories, id: \.self) { category in
                Section(category) {
                    ForEach(GraphTemplateCatalog.templates(in: category)) { template in
                        // A single Button per row — same reliable pattern as
                        // NodeLibrarySheet/LessonListView/ChallengeListView.
                        // This used to be two side-by-side Buttons (load +
                        // tour) sharing one row; two independent Buttons in
                        // one List row is a materially less reliable touch
                        // target on real devices than a single one, even
                        // with .contentShape set on both — the row's own
                        // tap-highlight machinery has to arbitrate between
                        // them, and that arbitration is where taps were
                        // getting swallowed. The tour is still one tap away,
                        // just via a swipe action instead — the fully
                        // native, always-reliable way iOS handles a
                        // secondary per-row action.
                        Button {
                            viewModel.loadTemplate(template)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                Text(template.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                lessonViewModel.start(GraphTourBuilder.tour(name: template.name, for: template.make()))
                                dismiss()
                            } label: {
                                Label("Tour", systemImage: "info.circle")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
