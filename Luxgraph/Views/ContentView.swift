import SwiftUI

/// Top-level composition: live preview strip + node canvas, top bar with
/// undo/redo, audio source picker, new graph, and the node library.
struct ContentView: View {
    @StateObject private var viewModel: GraphViewModel
    @StateObject private var lessonViewModel: LessonViewModel
    @StateObject private var challengeViewModel: ChallengeViewModel
    @ObservedObject private var externalDisplay = ExternalDisplayManager.shared
    @State private var showingLibrary = false
    @State private var showingTemplates = false
    @State private var showingFullscreen = false
    @State private var showingLessons = false
    @State private var showingChallenges = false
    @State private var showingMacros = false
    @State private var showingMatrix = false
    @State private var showingConnectionMatrix = false
    @State private var showingPatchBrowser = false
    @State private var showingSavePatch = false
    @State private var savePatchName = ""
    @State private var showingPerformanceMode = false
    @State private var showingShareSheet = false
    @State private var photosSaveState: PhotosSaveState = .idle

    private enum PhotosSaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    init() {
        let graphViewModel = GraphViewModel()
        _viewModel = StateObject(wrappedValue: graphViewModel)
        _lessonViewModel = StateObject(wrappedValue: LessonViewModel(store: graphViewModel.store))
        _challengeViewModel = StateObject(wrappedValue: ChallengeViewModel(store: graphViewModel.store))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if viewModel.store.previewHidden {
                        // Collapsed to a thin re-open bar rather than
                        // removed outright — most of the space goes back to
                        // canvas/controls, but there's still an obvious,
                        // one-tap way back, same idea as the Macro remote's
                        // fold tab.
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { viewModel.store.previewHidden = false }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.down")
                                Text("Show Preview")
                                if externalDisplay.isConnected {
                                    Label("Projector Connected", systemImage: "tv")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(white: 0.1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ZStack {
                            PreviewView(renderEngine: viewModel.renderEngine)
                            // The Metal view underneath has touch interaction
                            // disabled (it was intercepting taps meant for
                            // things SwiftUI draws above it, like the toolbar
                            // menu) — so the tap-to-fullscreen gesture lives on
                            // this plain, purely-SwiftUI transparent layer
                            // instead of directly on the Metal view, which
                            // would no longer receive it.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showingFullscreen = true }
                        }
                            .frame(height: proxy.size.height * 0.32)
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 8) {
                                    Button {
                                        recordButtonTapped()
                                    } label: {
                                        Image(systemName: viewModel.videoRecorder.isRecording ? "stop.circle.fill" : "record.circle")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(viewModel.videoRecorder.isRecording ? .red : .white.opacity(0.85))
                                            .padding(8)
                                            .background(.black.opacity(0.35), in: Circle())
                                    }
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.store.previewHidden = true }
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.85))
                                            .padding(8)
                                            .background(.black.opacity(0.35), in: Circle())
                                    }
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(8)
                                        .background(.black.opacity(0.35), in: Circle())
                                }
                                .padding(10)
                            }
                            .overlay(alignment: .top) {
                                if viewModel.videoRecorder.isRecording {
                                    Label(formattedElapsed, systemImage: "record.circle.fill")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.red.opacity(0.55), in: Capsule())
                                        .padding(.top, 8)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                // Confirms the external screen actually got the
                                // clean, controls-free feed — otherwise there's
                                // no on-screen sign anything special is
                                // happening when a projector connects.
                                if externalDisplay.isConnected {
                                    // The exact moment Performance Mode earns
                                    // its place — the projector already has
                                    // the clean visual, so this is the cue to
                                    // hand the whole phone/iPad screen over
                                    // to big, thumb-friendly macro faders.
                                    Button {
                                        showingPerformanceMode = true
                                    } label: {
                                        Label("Projector Connected — Perform", systemImage: "tv")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.black.opacity(0.45), in: Capsule())
                                    }
                                    .padding(10)
                                }
                            }
                    }

                    ZStack(alignment: .bottomTrailing) {
                        GraphCanvasView()
                            .environmentObject(viewModel.store)
                            .environmentObject(lessonViewModel)

                        VStack {
                            Spacer()
                            LessonOverlayView()
                            ChallengeOverlayView()
                        }
                        .environmentObject(lessonViewModel)
                        .environmentObject(challengeViewModel)
                        .allowsHitTesting(true)

                        if let selected = viewModel.selectedNodeID {
                            InspectorView(nodeID: selected)
                                .environmentObject(viewModel.store)
                                .frame(maxWidth: .infinity, alignment: .bottom)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Appears the moment the graph has its first macro —
                        // a fold-out remote for riding values live, not a
                        // canvas node (macros aren't part of the patch's
                        // visual layout) and not buried in a menu. Docked
                        // mid-trailing-edge specifically: top-trailing is the
                        // add-node FAB, bottom is Inspector/Lesson/Challenge
                        // — the vertical center of the edge is the one spot
                        // nothing else already claims.
                        if !viewModel.store.graph.macros.isEmpty {
                            MacroRemoteView()
                                .environmentObject(viewModel.store)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        }

                        // Always-on-screen add-node action — a fixed toolbar
                        // icon can end up buried under an open sheet/menu or
                        // just be a small target one-handed; a floating
                        // circular button pinned to the canvas itself (same
                        // role as VKO1's own FAB) is reachable no matter what
                        // else is on screen. Pinned to the TOP-trailing
                        // corner specifically — the Inspector panel and the
                        // Lesson/Challenge overlay banners are all
                        // bottom-anchored in this same ZStack, so a
                        // bottom-trailing FAB would end up sharing their
                        // corner and getting visually buried under whichever
                        // of those happens to be showing. Top-trailing (just
                        // under the preview strip) never overlaps any of them.
                        Button {
                            showingLibrary = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor, in: Circle())
                                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.selectedNodeID)
                }
            }
            .navigationTitle("Luxgraph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        viewModel.store.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!viewModel.store.canUndo)

                    Button {
                        viewModel.store.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!viewModel.store.canRedo)
                }
                // Two SEPARATE flat menus (File, Tools) rather than one
                // long 13-item list — that list was still passing 2 items
                // to `ToolbarItemGroup`'s own overflow logic, so it never
                // triggers iOS's own nested "..." (the earlier bug, fixed
                // separately by never nesting a Menu inside a Menu). This
                // split is instead about the list itself: past a certain
                // length, rows packed close together in one native Menu
                // become genuinely easy to mis-tap on a phone screen —
                // roughly halving it (by topic, so each grouping stays
                // predictable) gives every row more room and fewer
                // neighbors to miss.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        // Flat top-level buttons, not a nested Menu-in-Menu —
                        // a Menu containing another Menu as a sibling of
                        // plain Buttons is a known-flaky SwiftUI combo on
                        // real devices (opens fine, but tapping any item,
                        // including the OTHER top-level buttons, silently
                        // does nothing) even when it looks fine in
                        // Simulator. Only 2 audio sources exist, so there
                        // was no real need for a submenu here anyway.
                        ForEach(AudioSource.allCases) { source in
                            Button {
                                viewModel.audio.source = source
                            } label: {
                                if viewModel.audio.source == source {
                                    Label("Audio: \(source.rawValue)", systemImage: "checkmark")
                                } else {
                                    Label("Audio: \(source.rawValue)", systemImage: "waveform")
                                }
                            }
                        }
                        Button {
                            viewModel.newGraph()
                        } label: {
                            Label("New Graph", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showingTemplates = true
                        } label: {
                            Label("Templates", systemImage: "wand.and.stars")
                        }
                        Button {
                            savePatchName = viewModel.currentPatchName
                            showingSavePatch = true
                        } label: {
                            Label("Save Patch", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            showingPatchBrowser = true
                        } label: {
                            Label("My Patches", systemImage: "folder")
                        }
                        Button {
                            viewModel.store.cablesHidden.toggle()
                        } label: {
                            Label(viewModel.store.cablesHidden ? "Show Cables" : "Hide Cables",
                                  systemImage: viewModel.store.cablesHidden ? "eye.slash" : "eye")
                        }
                        Button {
                            viewModel.store.previewHidden.toggle()
                        } label: {
                            Label(viewModel.store.previewHidden ? "Show Preview" : "Hide Preview",
                                  systemImage: viewModel.store.previewHidden ? "rectangle.slash" : "rectangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Menu {
                        Button {
                            showingLessons = true
                        } label: {
                            Label("Lessons", systemImage: "graduationcap")
                        }
                        Button {
                            showingChallenges = true
                        } label: {
                            Label("Challenges", systemImage: "flag.checkered")
                        }
                        Button {
                            showingMacros = true
                        } label: {
                            Label("Macros", systemImage: "slider.horizontal.3")
                        }
                        Button {
                            showingPerformanceMode = true
                        } label: {
                            Label("Performance Mode", systemImage: "pianokeys")
                        }
                        Button {
                            showingMatrix = true
                        } label: {
                            Label("Macro Matrix", systemImage: "square.grid.3x3")
                        }
                        Button {
                            showingConnectionMatrix = true
                        } label: {
                            Label("Connection Matrix", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
            }
        }
        .sheet(isPresented: $showingLibrary) {
            NodeLibrarySheet().environmentObject(viewModel.store)
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateBrowserView()
                .environmentObject(viewModel)
                .environmentObject(lessonViewModel)
        }
        .sheet(isPresented: $showingPatchBrowser) {
            PatchBrowserView().environmentObject(viewModel)
        }
        .alert("Save Patch", isPresented: $showingSavePatch) {
            TextField("Name", text: $savePatchName)
            Button("Save") { viewModel.savePatch(named: savePatchName) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingLessons) {
            LessonListView().environmentObject(lessonViewModel)
        }
        .sheet(isPresented: $showingChallenges) {
            ChallengeListView().environmentObject(challengeViewModel)
        }
        .sheet(isPresented: $showingMacros) {
            MacroControlPanelView().environmentObject(viewModel.store)
        }
        .sheet(isPresented: $showingMatrix) {
            ModulationMatrixView().environmentObject(viewModel.store)
        }
        .sheet(isPresented: $showingConnectionMatrix) {
            ConnectionMatrixView().environmentObject(viewModel.store)
        }
        .fullScreenCover(isPresented: $showingPerformanceMode) {
            PerformanceModeView(onClose: { showingPerformanceMode = false })
                .environmentObject(viewModel.store)
        }
        .fullScreenCover(isPresented: $showingFullscreen) {
            FullscreenPreviewView(renderEngine: viewModel.renderEngine) {
                showingFullscreen = false
            }
        }
        .onChange(of: viewModel.videoRecorder.lastExportURL) { _, url in
            showingShareSheet = url != nil
            photosSaveState = .idle
        }
        .sheet(isPresented: $showingShareSheet, onDismiss: { viewModel.videoRecorder.lastExportURL = nil }) {
            if let url = viewModel.videoRecorder.lastExportURL {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Recording Ready").font(.headline)

                    Button {
                        photosSaveState = .saving
                        Task {
                            let result = await viewModel.videoRecorder.saveToPhotos(url: url)
                            photosSaveState = switch result {
                            case .saved: .saved
                            case .denied: .denied
                            case .failed: .failed
                            }
                        }
                    } label: {
                        Label(photosButtonTitle, systemImage: photosButtonIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(photosSaveState == .saving || photosSaveState == .saved)
                    if photosSaveState == .denied {
                        Text("Photos access was denied — enable it in Settings to save directly.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else if photosSaveState == .failed {
                        Text("Couldn't save to Photos — try again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    // A plain file URL to an .mov also lets the system share
                    // sheet hand the video directly to WhatsApp and similar
                    // apps as a playable attachment, not just a link.
                    ShareLink(item: url, preview: SharePreview("Luxgraph Recording")) {
                        Label("Share (WhatsApp, AirDrop...)", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(30)
                .presentationDetents([.height(290)])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var photosButtonTitle: String {
        switch photosSaveState {
        case .idle: return "Save to Photos"
        case .saving: return "Saving..."
        case .saved: return "Saved to Photos"
        case .denied: return "Access Denied"
        case .failed: return "Save Failed — Retry"
        }
    }

    private var photosButtonIcon: String {
        switch photosSaveState {
        case .saved: return "checkmark.circle.fill"
        case .denied, .failed: return "exclamationmark.triangle.fill"
        default: return "square.and.arrow.down"
        }
    }

    private func recordButtonTapped() {
        if viewModel.videoRecorder.isRecording {
            Task { _ = await viewModel.videoRecorder.stopRecording() }
        } else {
            viewModel.videoRecorder.startRecording(size: viewModel.renderEngine.recordingResolution)
        }
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.videoRecorder.elapsedSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    ContentView()
}
