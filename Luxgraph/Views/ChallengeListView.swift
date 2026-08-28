import SwiftUI

/// Ported from Modula's `ChallengeListView` (Patch -> Graph).
struct ChallengeListView: View {
    @EnvironmentObject var challengeViewModel: ChallengeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ChallengeLibrary.all) { challenge in
                    Button {
                        challengeViewModel.start(challenge)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: challenge.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(challenge.title)
                                    .foregroundStyle(.primary)
                                Text(challenge.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Challenges")
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
