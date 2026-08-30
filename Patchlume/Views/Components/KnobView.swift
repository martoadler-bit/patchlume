import SwiftUI

/// Rotary knob control, ported from Modula's `KnobView`. Vertical drag
/// changes value; double-tap resets to the parameter's default. Long-press
/// opens the inline-LFO editor (nil `modulator`/`onModulatorChange` skips
/// that entirely — used by the Inspector's compact rows, which use the
/// float-slider `ParameterRow` instead and don't need it duplicated).
struct KnobView: View {
    let label: String
    let parameter: ParameterDescriptor
    let value: Float
    let onChange: (Float) -> Void
    var modulator: ParamModulator? = nil
    var onModulatorChange: ((ParamModulator?) -> Void)? = nil

    @State private var dragStartValue: Float?
    @GestureState private var isDragging = false
    @State private var showingModulatorEditor = false

    private let diameter: CGFloat = 52
    private let dragSensitivity: CGFloat = 140

    private var normalized: Float { parameter.normalized(value) }
    private var angle: Angle { .degrees(Double(normalized) * 270 - 135) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.16))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                Circle()
                    .trim(from: 0, to: CGFloat(normalized))
                    .rotation(.degrees(-135))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(4)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: diameter * 0.32)
                    .offset(y: -diameter * 0.18)
                    .rotationEffect(angle)
                // A small pulsing dot marks a knob with an inline LFO
                // attached — same "modulated value" affordance Modula uses
                // on its Filter/Sampler knobs, just showing presence here
                // rather than a live sampled position.
                if modulator != nil {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                        .offset(y: -diameter / 2 - 5)
                }
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(isDragging ? 1.08 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            // Long-press and drag composed via `.exclusively(before:)`
            // (same fix already proven for Modula's port connect/disconnect
            // gesture) rather than as two separate stacked `.gesture`/
            // `.onLongPressGesture` modifiers: with two independent
            // recognizers, a hold that drifts past the drag's 2pt threshold
            // just before the long-press fires can leave `dragStartValue`
            // set from a drag that never got its `.onEnded`, corrupting the
            // very next drag's delta. `.exclusively` guarantees only one of
            // the two ever starts for a given touch.
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        guard onModulatorChange != nil else { return }
                        showingModulatorEditor = true
                    }
                    .exclusively(before:
                        DragGesture(minimumDistance: 2)
                            .updating($isDragging) { _, state, _ in state = true }
                            .onChanged { drag in
                                if dragStartValue == nil { dragStartValue = value }
                                let delta = Float(-drag.translation.height / dragSensitivity) * (parameter.maxValue - parameter.minValue)
                                let newValue = (dragStartValue! + delta).clamped(parameter.minValue, parameter.maxValue)
                                onChange(newValue)
                            }
                            .onEnded { _ in dragStartValue = nil }
                    )
            )
            .onTapGesture(count: 2) {
                onChange(parameter.defaultValue)
            }
            .sheet(isPresented: $showingModulatorEditor) {
                if let onModulatorChange {
                    ParamModulatorSheet(paramLabel: label, modulator: modulator, onSave: onModulatorChange)
                }
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var valueText: String {
        if parameter.unit.isEmpty {
            return String(format: "%.2f", value)
        }
        return String(format: "%.0f%@", value, parameter.unit)
    }
}
