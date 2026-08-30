import SwiftUI

/// A collapsible "remote control" dock for live-riding macros, distinct
/// from both the canvas (macros aren't nodes — they don't clutter the
/// patch) and the Macros management sheet (adding/removing macros and
/// wiring targets still happens there; this is purely for touching values
/// while watching the preview). Appears automatically the moment the graph
/// has its first macro, folded to a small edge tab by default — tap it to
/// slide out up to 8 macro sliders, tap again to fold back away.
struct MacroRemoteView: View {
    @EnvironmentObject var store: GraphStore
    @State private var expanded = false

    private var macros: [Macro] { Array(store.graph.macros.prefix(8)) }

    var body: some View {
        HStack(spacing: 0) {
            if expanded {
                VStack(spacing: 14) {
                    ForEach(macros) { macro in
                        VStack(spacing: 4) {
                            Text(macro.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .frame(width: 92)
                            Slider(value: Binding(
                                get: { macro.value },
                                set: { store.updateMacroValue(id: macro.id, value: $0) }
                            ), in: 0...1)
                            .frame(width: 92)
                            Text(String(format: "%.0f%%", macro.value * 100))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 8, x: -2, y: 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.compact.right" : "chevron.compact.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 64)
                    .background(Color.accentColor)
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 10, bottomLeading: 10), style: .continuous))
        }
    }
}
