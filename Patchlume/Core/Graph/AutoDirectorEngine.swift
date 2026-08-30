import Combine
import CoreGraphics
import Foundation

/// Unattended "auto-pilot" mode — meant for exactly the case that prompted
/// it: point the phone/iPad's camera at a rehearsal, turn this on, and
/// Patchlume rotates through curated scenes on its own (`AutoDirectorScenes`),
/// leaning toward livelier camera/hybrid scenes when the room is loud and
/// toward calmer generative ones when it's quiet, crossfading smoothly
/// between one scene and the next instead of hard-cutting.
///
/// Deliberately does NOT touch `GraphStore`'s undo stack while running
/// (`resetHistory: false` on every load) — the whole point is nobody's
/// meant to be driving the canvas during a show; undo history for THIS
/// session's auto-generated churn would just be noise if they come back
/// to edit by hand afterward.
@MainActor
final class AutoDirectorEngine: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var currentSceneName = ""
    /// User-facing constraints (mood emphasis, pace, NDI/shot-change/color
    /// opt-outs) — loaded from `UserDefaults` on init, saved back on every
    /// change so they persist across launches. Every default matches this
    /// engine's original hardcoded behavior exactly; touching the settings
    /// sheet is the only thing that changes anything.
    @Published var settings: DirectorSettings = .loadFromDefaults() {
        didSet {
            guard settings != oldValue else { return }
            settings.saveToDefaults()
        }
    }

    private weak var store: GraphStore?
    private let audio: AudioReactivityEngine
    private let cameraEngine: CameraCaptureEngine
    private let crossfader: SceneCrossfader
    private let ndiSourceEngine: NDISourceEngine

    /// A color "moment" the director can push the room toward — cycles on
    /// its own schedule, independent of (and usually shorter than) scene
    /// duration, so a single scene can pass through more than one of
    /// these. Only ever touches macros literally named "Saturation" (every
    /// scene's camera/hue-rotate node exposes one for exactly this) —
    /// nothing else about the scene changes.
    private enum ColorMood: CaseIterable {
        case natural, monochrome, oversaturated, splitCameraBW, splitCameraColor
    }

    private var sceneTimer: Timer?
    private var macroRiderTimer: Timer?
    private var colorMoodTimer: Timer?
    private var shotChangeTimer: Timer?

    /// How often macros get nudged, and by how much per nudge — tuned to
    /// read as continuous "performing" rather than either a static value
    /// or a visibly steppy jump.
    private let macroRiderInterval: TimeInterval = 0.4
    private let macroDriftRange: ClosedRange<Float> = -0.06...0.06
    /// How often the color mood changes — shorter than a scene's own
    /// lifetime on purpose, so "b&w moment" / "oversaturated moment" /
    /// "camera b&w, rest in color" read as things that happen a couple
    /// times PER scene, not just once per scene change.
    private let colorMoodDurationRange: ClosedRange<Double> = 12...22
    /// How often the "shot" (which physical lens is live) can change —
    /// shorter than a scene's own lifetime, same idea as color mood, so a
    /// wide establishing shot cutting to a close-up (and back) happens a
    /// few times within one scene, not just once at the scene boundary.
    private let shotChangeDurationRange: ClosedRange<Double> = 8...16
    /// Saturation macros currently chasing a color-mood target, keyed by
    /// macro id — refreshed every color-mood tick, read by `rideMacros()`
    /// each rider tick so the two systems compose instead of fighting.
    private var saturationTargets: [UUID: Float] = [:]
    /// The last few scene names played, most recent last — `pickScene()`
    /// excludes all of them from the pool, not just the immediately
    /// previous one, so the rotation actually spreads across the library
    /// instead of visibly bouncing between a handful of scenes.
    private var recentSceneNames: [String] = []
    private let recentSceneHistoryLimit = 5
    /// Whether the scene currently on screen is one of the NDI-dependent
    /// ones — checked on every `ndiSourceEngine.isConnected` change so a
    /// mid-scene disconnect cuts away immediately instead of sitting on a
    /// half-black frame until the next scheduled transition.
    private var currentSceneRequiresNDI = false
    private var ndiCancellable: AnyCancellable?

    init(store: GraphStore, audio: AudioReactivityEngine, cameraEngine: CameraCaptureEngine, crossfader: SceneCrossfader, ndiSourceEngine: NDISourceEngine) {
        self.store = store
        self.audio = audio
        self.cameraEngine = cameraEngine
        self.crossfader = crossfader
        self.ndiSourceEngine = ndiSourceEngine
        self.ndiCancellable = ndiSourceEngine.$isConnected.sink { [weak self] _ in
            Task { @MainActor in self?.handleNDIConnectionChange() }
        }
    }

    func start() {
        guard !isActive, let store else { return }
        isActive = true
        let first = pickScene()
        currentSceneName = first.name
        currentSceneRequiresNDI = first.requiresNDI
        store.load(first.make(), resetHistory: false)
        updateShot()
        scheduleNextTransition()
        startMacroRider()
        applyColorMood()
        scheduleNextColorMood()
        scheduleNextShotChange()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        sceneTimer?.invalidate(); sceneTimer = nil
        macroRiderTimer?.invalidate(); macroRiderTimer = nil
        colorMoodTimer?.invalidate(); colorMoodTimer = nil
        shotChangeTimer?.invalidate(); shotChangeTimer = nil
        saturationTargets.removeAll()
        recentSceneNames.removeAll()
    }

    /// Fires whenever `NDISourceEngine.isConnected` changes — a brand-new
    /// connection just widens what the NEXT shot change / scheduled scene
    /// transition can pick (no need to act immediately). A disconnect needs
    /// two different responses depending on how NDI is in use right now:
    /// if the whole current scene depends on it ("Two Cameras Blend" is
    /// only ever picked as `requiresNDI`), that half of the frame just went
    /// black, so cut to a different scene entirely rather than wait for the
    /// next scheduled transition. Otherwise, if `updateShot()`'s own coin
    /// flip happened to be showing NDI on an ordinary camera-forward scene
    /// right now, it's a single node — swap just that node back to the
    /// local camera instead of a full scene change.
    private func handleNDIConnectionChange() {
        guard isActive, !ndiSourceEngine.isConnected else { return }
        if currentSceneRequiresNDI {
            sceneTimer?.invalidate()
            beginTransition()
        } else if let store, let node = store.graph.nodes.first(where: { $0.kind == .generator && $0.subtype == "ndiSource" }) {
            store.updateSubtype(nodeID: node.id, subtype: "camera", recordUndo: false)
            let lens: Float = cameraEngine.hasFace ? 1 : 2
            store.updateParameter(nodeID: node.id, paramID: "p2", value: lens, recordUndo: false)
        }
    }

    /// The part that actually makes this feel like it's "listening" rather
    /// than just cycling scenes that each loop the same baked-in LFO:
    /// every tick, every macro on the CURRENT graph takes a small random
    /// step, biased by the room's live audio energy — a loud room pushes
    /// macros up (and does so more per tick), a quiet room lets them settle
    /// back down. `GraphStore.updateMacroValue` already exists for exactly
    /// this kind of continuous live riding (same call a finger dragging a
    /// macro fader in Performance Mode makes) and is deliberately not
    /// undo-snapshotted.
    private func startMacroRider() {
        macroRiderTimer = Timer.scheduledTimer(withTimeInterval: macroRiderInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rideMacros() }
        }
    }

    private func rideMacros() {
        guard let store else { return }
        let energy = audio.state.energy
        // Centered so a quiet room (energy well below 0.35) gently pulls
        // macros down over time instead of just idling wherever a loud
        // moment last left them.
        let audioPull = (energy - 0.35) * 0.18
        for macro in store.graph.macros {
            if let target = saturationTargets[macro.id] {
                // Color-mood macros ease toward their target (a smooth
                // several-second "grade" rather than a hard cut to b&w),
                // with a touch of the same audio/random life so a held b&w
                // moment doesn't go completely static.
                let eased = macro.value + (target - macro.value) * 0.15
                store.updateMacroValue(id: macro.id, value: eased + Float.random(in: -0.015...0.015))
            } else {
                let drift = Float.random(in: macroDriftRange)
                store.updateMacroValue(id: macro.id, value: macro.value + drift + audioPull)
            }
        }
    }

    private func scheduleNextColorMood() {
        let delay = Double.random(in: colorMoodDurationRange)
        colorMoodTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyColorMood()
                self?.scheduleNextColorMood()
            }
        }
    }

    /// Picks a new color mood and assigns every "Saturation" macro in the
    /// CURRENT graph a fresh target — `rideMacros()` eases each one there
    /// over the following seconds. `.splitCameraBW`/`.splitCameraColor`
    /// tell a camera's saturation macro apart from everyone else's by
    /// checking what node it's actually routed to (`subtype == "camera"`),
    /// not by name — so "camera in b&w, the rest in full color" falls out
    /// naturally instead of needing a separate authored mechanism.
    private func applyColorMood() {
        guard settings.colorMoodShifts else { return }
        guard let store else { return }
        let graph = store.graph
        let saturationMacros = graph.macros.filter { $0.name.localizedCaseInsensitiveContains("saturation") }
        guard !saturationMacros.isEmpty else { return }

        let mood = ColorMood.allCases.randomElement() ?? .natural
        for macro in saturationMacros {
            let isCamera = graph.macroAssignments.contains {
                $0.macroID == macro.id && graph.node($0.nodeID)?.subtype == "camera"
            }
            let target: Float
            switch mood {
            case .natural: target = 0.5
            case .monochrome: target = 0.0
            case .oversaturated: target = 1.0
            case .splitCameraBW: target = isCamera ? 0.0 : 1.0
            case .splitCameraColor: target = isCamera ? 1.0 : 0.0
            }
            saturationTargets[macro.id] = target
        }
    }

    private func scheduleNextShotChange() {
        let delay = Double.random(in: shotChangeDurationRange)
        shotChangeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateShot()
                self?.scheduleNextShotChange()
            }
        }
    }

    /// How often, on a shot-change tick with an NDI source actually
    /// connected, the shot swaps to that second device instead of staying
    /// on the local camera — deliberately well under 50% so the local
    /// camera stays the default "home" shot and NDI reads as a cutaway,
    /// not a coin flip between two equal options.
    private let ndiShotChance = 0.35

    /// Picks what's live on the scene's single camera/NDI generator node —
    /// which physical source (local camera vs. a connected second device
    /// over NDI, if any), and if it's the local camera, which lens (Back
    /// or Ultra Wide; front stays out of the rotation — the whole point of
    /// this mode is pointing a rear lens at the room). Runs on every scene
    /// that has such a node, not just the dedicated "Two Cameras Blend"
    /// template — so a second device connecting mid-show widens what EVERY
    /// camera-forward scene can show, and disconnecting narrows it back,
    /// without needing a special per-scene flag the way the always-both
    /// "Two Cameras Blend" scene does (`requiresNDI`).
    ///
    /// Leans on whether AVFoundation's face detector currently sees someone
    /// in frame for the lens choice: Back (close-up/mid, next to the
    /// ultra-wide) when there's a face, Ultra Wide (wide establishing shot)
    /// when there isn't — the "general -> close-up" cut a lens swap gives
    /// for free, made to happen on purpose instead of by luck. Still has
    /// real randomness on either side so neither choice reads as a rigid
    /// if/else. Swapping the node's subtype (`GraphStore.updateSubtype`) is
    /// cheap and instant — no crossfade needed, same as a real camera
    /// operator punching a different source on a switcher.
    private func updateShot() {
        guard settings.autoShotChanges else { return }
        guard let store, let node = store.graph.nodes.first(where: {
            $0.kind == .generator && ($0.subtype == "camera" || $0.subtype == "ndiSource")
        }) else { return }

        let useNDI = ndiSourceEngine.isConnected && settings.useNDIWhenConnected && Double.random(in: 0..<1) < ndiShotChance
        let newSubtype = useNDI ? "ndiSource" : "camera"
        if node.subtype != newSubtype {
            store.updateSubtype(nodeID: node.id, subtype: newSubtype, recordUndo: false)
        }
        guard !useNDI else { return } // no lens concept on an NDI source

        let closeUpChance: Double = cameraEngine.hasFace ? 0.8 : 0.25
        let lens: Float = Double.random(in: 0..<1) < closeUpChance ? 1 : 2 // Back (close) : Ultra Wide (wide)
        store.updateParameter(nodeID: node.id, paramID: "p2", value: lens, recordUndo: false)
    }

    private func scheduleNextTransition() {
        let delay = Double.random(in: settings.pace.sceneDurationRange)
        sceneTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.beginTransition() }
        }
    }

    /// Leans mood selection on the room's current energy rather than
    /// picking uniformly at random — loud/lively biases toward
    /// camera/hybrid scenes, quiet biases toward calmer generative ones.
    /// Weighting via a repeated-candidates pool (not a hard filter) so
    /// there's always variety, just tilted.
    private func pickScene() -> AutoDirectorScenes.Scene {
        let energy = audio.state.energy
        let weights: [AutoDirectorScenes.Scene.Mood: Int]
        if energy > 0.55 {
            weights = [.camera: 3, .hybrid: 3, .generative: 1]
        } else if energy > 0.25 {
            weights = [.camera: 2, .hybrid: 2, .generative: 2]
        } else {
            weights = [.camera: 1, .hybrid: 1, .generative: 3]
        }
        // Excludes not just the current scene but the last few played, so
        // a small pool (or a mood weighting that happens to favor a
        // handful of scenes in a row) doesn't visibly ping-pong between
        // the same 2-3 scenes.
        // NDI-dependent scenes only enter the pool while a second device is
        // actually connected AND the user hasn't opted out of NDI in the
        // Director settings — otherwise they'd just be a black half of the
        // frame with nobody there to notice or fix it.
        let ndiConnected = ndiSourceEngine.isConnected && settings.useNDIWhenConnected
        var eligible = AutoDirectorScenes.all.filter { ndiConnected || !$0.requiresNDI }
        switch settings.moodEmphasis {
        case .all: break
        case .cameraOnly: eligible = eligible.filter { $0.mood == .camera || $0.mood == .hybrid }
        case .generativeOnly: eligible = eligible.filter { $0.mood == .generative }
        }
        var pool: [AutoDirectorScenes.Scene] = []
        for scene in eligible where !recentSceneNames.contains(scene.name) {
            let weight = weights[scene.mood] ?? 1
            pool.append(contentsOf: Array(repeating: scene, count: weight))
        }
        let chosen = pool.randomElement()
            ?? eligible.first { $0.name != currentSceneName } // history excluded everything — just avoid an immediate repeat
            ?? eligible.randomElement()!
        recentSceneNames.append(chosen.name)
        if recentSceneNames.count > recentSceneHistoryLimit { recentSceneNames.removeFirst() }
        return chosen
    }

    /// Kicks off a crossfade to a freshly picked scene via the shared
    /// `SceneCrossfader`. The NEXT scene's own timer is scheduled right
    /// away — deliberately not inside the crossfade's completion — so a
    /// manual Scene Bank tap interrupting this crossfade (the crossfader
    /// cancels whichever transition was already in flight) can't silently
    /// stall the director's rotation; only the "did THIS crossfade land
    /// cleanly" follow-up (name/lens/color-mood bookkeeping) waits for it.
    private func beginTransition() {
        scheduleNextTransition()
        let next = pickScene()
        crossfader.crossfade(to: next.make()) { [weak self] in
            guard let self else { return }
            self.currentSceneName = next.name
            self.currentSceneRequiresNDI = next.requiresNDI
            self.updateShot()
            self.applyColorMood()
        }
    }
}
