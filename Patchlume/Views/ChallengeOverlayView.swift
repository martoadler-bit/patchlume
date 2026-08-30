import SwiftUI

/// The active-Challenge control card. Ported from Modula's
/// `ChallengeOverlayView`; unlike Modula (no hidden target to reveal —
/// Patchlume's graph is fully visible structural state, not audio), this one
/// offers two other kinds of help a stuck player can reach for: a text
/// `Hint`, and "Show Me", which plays the challenge's solution onto the
/// canvas one step at a time — same self-building mechanism a Lesson uses.
struct ChallengeOverlayView: View {
    @EnvironmentObject var challengeViewModel: ChallengeViewModel

    var body: some View {
        if let challenge = challengeViewModel.activeChallenge {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: challenge.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(challenge.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        challengeViewModel.exit()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: challengeViewModel.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(challengeViewModel.isComplete ? Color.green : Color.secondary)
                    Text(challengeViewModel.isComplete ? "Complete!" : "Not complete yet — keep building.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(challengeViewModel.isComplete ? Color.green : Color.secondary)
                }
                .animation(.easeInOut(duration: 0.2), value: challengeViewModel.isComplete)

                if challengeViewModel.hintVisible {
                    Text(challenge.hint)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }

                if !challengeViewModel.isComplete {
                    HStack(spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { challengeViewModel.toggleHint() }
                        } label: {
                            Label(challengeViewModel.hintVisible ? "Hide Hint" : "Hint", systemImage: "lightbulb")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)

                        if challengeViewModel.hasSolution {
                            Button {
                                challengeViewModel.playNextSolutionStep()
                            } label: {
                                Label(showMeLabel, systemImage: "wand.and.stars")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    private var showMeLabel: String {
        guard let progress = challengeViewModel.solutionProgress else { return "Show Me" }
        return progress.current >= progress.total ? "Show Me" : "Next Step (\(progress.current)/\(progress.total))"
    }
}
