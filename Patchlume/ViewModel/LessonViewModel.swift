import CoreGraphics
import Foundation
import SwiftUI

/// Drives an active lesson: which step we're on, what to highlight, and
/// loading whatever graph that step wants onto the real canvas via
/// `GraphStore`. Most steps are read-and-try-it-yourself, advanced manually
/// with Next — deliberately no "did the user actually do it" verification,
/// which keeps the content honest about what it can and can't check. A step
/// can instead carry `buildActions`: one gets applied to the canvas per tap
/// of Next, with its caption in the speech bubble, so a tutorial builds
/// itself at the user's own pace rather than racing ahead on a timer.
/// Ported from Modula's `LessonViewModel` (Module -> Node, Patch -> Graph).
@MainActor
final class LessonViewModel: ObservableObject {
    @Published private(set) var activeLesson: Lesson?
    @Published private(set) var stepIndex: Int = 0
    @Published private(set) var highlightedKind: NodeKind?
    @Published private(set) var highlightedSubtype: String?
    /// The exact node instance the current step is about, when known —
    /// distinct from `highlightedKind` because a graph can have more than
    /// one node of the same kind. The canvas pans/zooms to this node
    /// whenever it changes.
    @Published private(set) var focusNodeID: UUID?
    @Published private(set) var narration: String = ""
    @Published private(set) var buildActionIndex: Int = 0

    private let store: GraphStore
    private var refToNodeID: [String: UUID] = [:]

    init(store: GraphStore) {
        self.store = store
    }

    var currentStep: LessonStep? {
        guard let lesson = activeLesson, stepIndex < lesson.steps.count else { return nil }
        return lesson.steps[stepIndex]
    }

    /// Non-nil while the current step still has build actions left to play,
    /// so the overlay can show "action 3 of 10" alongside the step count.
    var buildProgress: (current: Int, total: Int)? {
        guard let actions = currentStep?.buildActions, !actions.isEmpty else { return nil }
        return (buildActionIndex + 1, actions.count)
    }

    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool {
        guard let lesson = activeLesson else { return true }
        return stepIndex == lesson.steps.count - 1
    }

    func start(_ lesson: Lesson) {
        activeLesson = lesson
        stepIndex = 0
        applyCurrentStep()
    }

    /// Advances one build action if the current step still has more queued
    /// up; only moves to the next lesson step once they're exhausted.
    func next() {
        guard let lesson = activeLesson else { return }
        if let step = currentStep, buildActionIndex < step.buildActions.count - 1 {
            buildActionIndex += 1
            applyBuildAction(at: buildActionIndex, in: step)
            return
        }
        if stepIndex < lesson.steps.count - 1 {
            stepIndex += 1
            applyCurrentStep()
        } else {
            exit()
        }
    }

    /// Always goes back a whole lesson step (not one build action at a
    /// time) — simpler and more predictable than trying to precisely
    /// reverse an individual add/connect.
    func back() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        applyCurrentStep()
    }

    func exit() {
        activeLesson = nil
        stepIndex = 0
        highlightedKind = nil
        highlightedSubtype = nil
        focusNodeID = nil
    }

    private func applyCurrentStep() {
        guard let step = currentStep else { return }
        highlightedKind = step.highlightKind
        highlightedSubtype = step.highlightSubtype
        focusNodeID = step.highlightNodeID
        narration = step.text
        buildActionIndex = 0

        if !step.buildActions.isEmpty {
            refToNodeID = [:]
            store.load(Graph.empty)
            applyBuildAction(at: 0, in: step)
        } else if let graph = step.graphToLoad {
            store.load(graph)
        }
    }

    private func applyBuildAction(at index: Int, in step: LessonStep) {
        guard index < step.buildActions.count else { return }
        let action = step.buildActions[index]
        if let caption = action.caption {
            narration = caption
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            action.apply(to: store, refToNodeID: &refToNodeID)
        }
    }
}
