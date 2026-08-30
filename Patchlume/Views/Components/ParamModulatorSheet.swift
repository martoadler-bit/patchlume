import SwiftUI

/// Long-press a canvas knob to open this — attach, tune, or remove an
/// inline LFO on that one parameter, no cable or Input node needed.
struct ParamModulatorSheet: View {
    let paramLabel: String
    let onSave: (ParamModulator?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rate: Float
    @State private var depth: Float
    @State private var shape: Int
    @State private var wasAlreadyOn: Bool

    private static let shapeNames = ["Sine", "Triangle", "Square", "Saw"]

    init(paramLabel: String, modulator: ParamModulator?, onSave: @escaping (ParamModulator?) -> Void) {
        self.paramLabel = paramLabel
        self.onSave = onSave
        let seed = modulator ?? ParamModulator()
        _rate = State(initialValue: seed.rate)
        _depth = State(initialValue: seed.depth)
        _shape = State(initialValue: seed.shape)
        _wasAlreadyOn = State(initialValue: modulator != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Rides \(paramLabel) up and down on its own — stacks with anything already patched into this node's mod port.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Rate") {
                    Slider(value: $rate, in: 0.05...8) { Text("Rate") }
                    Text(String(format: "%.2f Hz", rate)).font(.caption).foregroundStyle(.secondary)
                }
                Section("Depth") {
                    Slider(value: $depth, in: 0...1) { Text("Depth") }
                    Text(String(format: "%.0f%% of range", depth * 100)).font(.caption).foregroundStyle(.secondary)
                }
                Section("Shape") {
                    Picker("Shape", selection: $shape) {
                        ForEach(Array(Self.shapeNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if wasAlreadyOn {
                    Section {
                        Button("Remove Modulation", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Modulate \(paramLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(wasAlreadyOn ? "Update" : "Add") {
                        onSave(ParamModulator(rate: rate, depth: depth, shape: shape))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
