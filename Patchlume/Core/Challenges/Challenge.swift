import Foundation

/// A concrete, programmatically-checkable task against the live graph —
/// e.g. "add a Generator" or "wire an audio Input into a mod port". Unlike
/// Modula's ear-training `Challenge` (a hidden target patch compared only
/// by module-kind counts, since audio can't be inspected structurally),
/// Patchlume's graph state is fully inspectable, so completion is a plain
/// boolean predicate evaluated live against `GraphStore`.
struct Challenge: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let icon: String
    /// One line of guidance, revealed on demand — what to do, without doing
    /// it for the player.
    let hint: String
    /// A scripted, node-by-node build (same `TutorialAction` type Lessons
    /// use) that satisfies this challenge from a blank canvas — played back
    /// one step per tap of "Show Me" in `ChallengeOverlayView`, exactly like
    /// a Lesson's self-building steps. Empty for challenges that aren't
    /// about graph structure at all (e.g. the cable-visibility toggle).
    let solution: [TutorialAction]
    /// Evaluated live (see `ChallengeViewModel`) against the current store.
    /// Takes the whole store rather than just `Graph` so a challenge can
    /// also check canvas state like `cablesHidden`.
    let isComplete: @MainActor (GraphStore) -> Bool
}
