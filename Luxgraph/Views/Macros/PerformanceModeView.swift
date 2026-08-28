import SwiftUI

/// Full-screen, thumb-friendly macro control surface — a mixing-console
/// style bank of tall vertical faders, one per macro, meant to be the ONLY
/// thing on screen while casting: the clean visual is already on the
/// external display (see `ExternalDisplayManager`), so the phone/iPad can
/// give 100% of its screen to comfortable live control instead of also
/// showing the canvas/graph. Reachable from the Tools menu, or the quick
/// button next to the "Projector Connected" badge the moment a projector
/// actually connects — that's the exact moment this view earns its place.
///
/// Laid out on a fixed 4-column grid (up to 8 macros — the same cap the
/// Macro remote uses — fit in two rows with no scrolling needed) rather
/// than a single scrolling row, and each fader's height adapts to however
/// many rows are actually in play so the whole bank always fits the
/// screen without spilling off it.
struct PerformanceModeView: View {
    @EnvironmentObject var store: GraphStore
    let onClose: () -> Void

    @State private var renamingMacro: Macro?
    @State private var renameText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    private let reservedPerRow: CGFloat = 96 // label + name + spacing, per row

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.08), Color.black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if store.graph.macros.isEmpty {
                ContentUnavailableView("No Macros to Perform", systemImage: "slider.vertical.3",
                    description: Text("Add a macro from the Macros panel first — Performance Mode is a big-fader view of your macros."))
                    .foregroundStyle(.white)
            } else {
                GeometryReader { proxy in
                    let macros = Array(store.graph.macros.prefix(8))
                    let rowCount = max(1, Int(ceil(Double(macros.count) / 4.0)))
                    let availableHeight = proxy.size.height - 90 // top/bottom padding
                    let faderHeight = min(max(availableHeight / CGFloat(rowCount) - reservedPerRow, 90), 320)

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(macros) { macro in
                            faderCard(macro, faderHeight: faderHeight)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 70)
                    .padding(.bottom, 20)
                }
            }

            VStack {
                HStack {
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
        .alert("Rename Macro", isPresented: Binding(get: { renamingMacro != nil }, set: { if !$0 { renamingMacro = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let macro = renamingMacro { store.renameMacro(id: macro.id, name: renameText) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func faderCard(_ macro: Macro, faderHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text(String(format: "%.0f%%", macro.value * 100))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))

            VerticalFader(value: macro.value, height: faderHeight) { newValue in
                store.updateMacroValue(id: macro.id, value: newValue)
            }

            Button {
                renameText = macro.name
                renamingMacro = macro
            } label: {
                HStack(spacing: 4) {
                    Text(macro.name).lineLimit(1)
                    Image(systemName: "pencil").font(.system(size: 9))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// Direct-manipulation vertical fader — tap or drag anywhere on the track
/// jumps the value there and tracks the finger, which reads as more
/// "instrument-like" for live performance than dragging a small native
/// `Slider` thumb along a rotated axis.
private struct VerticalFader: View {
    let value: Float
    let height: CGFloat
    let onChange: (Float) -> Void

    private let width: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let filled = geo.size.height * CGFloat(value.clamped(0, 1))
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                          startPoint: .bottom, endPoint: .top))
                    .frame(height: filled)
                Capsule()
                    .fill(Color.white)
                    .frame(width: width + 14, height: 6)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: -filled + 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedY = min(max(drag.location.y, 0), geo.size.height)
                        onChange(Float(1 - clampedY / geo.size.height))
                    }
            )
        }
        .frame(width: width, height: height)
    }
}
