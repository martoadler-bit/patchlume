import SwiftUI

/// Ported from Modula's `LessonListView` (Patch -> Graph).
struct LessonListView: View {
    @EnvironmentObject var lessonViewModel: LessonViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(LessonLibrary.all) { lesson in
                    Button {
                        lessonViewModel.start(lesson)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: lesson.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.title)
                                    .foregroundStyle(.primary)
                                Text(lesson.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(lesson.steps.count) steps")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
