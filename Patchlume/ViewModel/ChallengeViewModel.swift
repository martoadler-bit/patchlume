import Combine
import Foundation
import SwiftUI

/// Drives an active Challenge: starts the player on a blank graph (just an
/// Output node) and re-evaluates the challenge's `isComplete` predicate live
/// against `GraphStore` every time the graph changes, via `store`'s own
/// `objectWillChange`. Also drives the two forms of help
/// `ChallengeOverlayView` offers: revealing `Challenge.hint`'s text, and
/// playing `Challenge.solution` (the same `TutorialAction` build-step
/// mechanism Lessons use) one step per tap — letting the app finish the
/// challenge for a stuck player exactly the way a Lesson builds itself.
@MainActor
final class ChallengeViewModel: ObservableObject {
    @Published private(set) var activeChallenge: Challenge?
    @Published private(set) var isComplete = false
    @Published private(set) var hintVisible = false
    /// nil while not playing the solution; the index of the last-applied
    /// step once playback has started.
    @Published private(set) var solutionStepIndex: Int?

    private let store: GraphStore
    private var cancellable: AnyCancellable?
    private var refToNodeID: [String: UUID] = [:]

    init(store: GraphStore) {
        self.store = store
    }

    var hasSolution: Bool { !(activeChallenge?.solution.isEmpty ?? true) }
    var isPlayingSolution: Bool { solutionStepIndex != nil }
    var solutionProgress: (current: Int, total: Int)? {
        guard let challenge = activeChallenge, let index = solutionStepIndex else { return nil }
        return (index + 1, challenge.solution.count)
    }

    func start(_ challenge: Challenge) {
        activeChallenge = challenge
        isComplete = false
        hintVisible = false
        solutionStepIndex = nil
        store.load(Graph.empty)
        store.addNode(kind: .output, subtype: "output")
        subscribe()
        evaluate()
    }

    func exit() {
        activeChallenge = nil
        isComplete = false
        hintVisible = false
        solutionStepIndex = nil
        cancellable = nil
    }

    func toggleHint() {
        hintVisible.toggle()
    }

    /// Plays one more step of the solution. The first tap resets to a blank
    /// canvas (the solution's own steps build everything it needs,
    /// including its own Output node) so playback always starts from a
    /// known state rather than layering onto whatever the player already
    /// built. Wraps back to "not playing" once every step has run, so
    /// tapping again after completion restarts it.
    func playNextSolutionStep() {
        guard let challenge = activeChallenge, !challenge.solution.isEmpty else { return }
        let nextIndex = (solutionStepIndex ?? -1) + 1
        guard nextIndex < challenge.solution.count else {
            solutionStepIndex = nil
            return
        }
        if nextIndex == 0 {
            refToNodeID = [:]
            store.load(Graph.empty)
        }
        solutionStepIndex = nextIndex
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            challenge.solution[nextIndex].apply(to: store, refToNodeID: &refToNodeID)
        }
    }

    private func subscribe() {
        cancellable = store.objectWillChange
            .sink { [weak self] _ in
                // objectWillChange fires just before the mutation lands, so
                // hop one runloop turn to evaluate against the settled state.
                DispatchQueue.main.async { self?.evaluate() }
            }
    }

    private func evaluate() {
        guard let challenge = activeChallenge else { return }
        isComplete = challenge.isComplete(store)
    }
}
