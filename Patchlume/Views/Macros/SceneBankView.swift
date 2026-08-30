import SwiftUI

/// The manual counterpart to `AutoDirectorEngine`: the same 26-scene
/// curated library (`AutoDirectorScenes`), laid out as a tappable grid a
/// performer can trigger by hand — each tap crossfades to that scene
/// through the exact same `SceneCrossfader` the director uses, instead of
/// hard-cutting like loading a template from the library does. Meant to
/// live right alongside Performance Mode: point the camera at the show,
/// then improvise by tapping scenes instead of (or in addition to) letting
/// the director pick them on its own.
struct SceneBankView: View {
    @ObservedObject var crossfader: SceneCrossfader
    let onClose: () -> Void

    @State private var pendingSceneName: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.08), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Camera", scenes: AutoDirectorScenes.all.filter { $0.mood == .camera })
                    section("Hybrid", scenes: AutoDirectorScenes.all.filter { $0.mood == .hybrid })
                    section("Generative", scenes: AutoDirectorScenes.all.filter { $0.mood == .generative })
                }
                .padding(.horizontal, 16)
                .padding(.top, 70)
                .padding(.bottom, 40)
            }

            VStack {
                HStack {
                    if crossfader.isTransitioning {
                        Label("Transitioning…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .padding(.leading, 20)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(20)
                }
                Spacer()
            }
        }
        .statusBarHidden(true)
    }

    private func section(_ title: String, scenes: [AutoDirectorScenes.Scene]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(scenes, id: \.name) { scene in
                    sceneButton(scene)
                }
            }
        }
    }

    private func sceneButton(_ scene: AutoDirectorScenes.Scene) -> some View {
        let isPending = pendingSceneName == scene.name
        return Button {
            pendingSceneName = scene.name
            crossfader.crossfade(to: scene.make()) {
                if pendingSceneName == scene.name { pendingSceneName = nil }
            }
        } label: {
            Text(scene.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(isPending ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(isPending ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isPending ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
