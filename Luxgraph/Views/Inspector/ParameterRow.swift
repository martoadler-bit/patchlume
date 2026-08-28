import SwiftUI

/// One parameter's control row inside the inspector, dispatching on
/// `ParameterDescriptor.type`.
struct ParameterRow: View {
    let parameter: ParameterDescriptor
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.label).font(.subheadline)
                Spacer()
                Text(valueText).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
            }
            switch parameter.type {
            case .float:
                Slider(value: Binding(get: { value }, set: onChange), in: parameter.minValue...parameter.maxValue)
            case .int:
                Stepper(value: Binding(get: { Int(value) }, set: { onChange(Float($0)) }), in: Int(parameter.minValue)...Int(parameter.maxValue)) {
                    EmptyView()
                }
            case .bool:
                Toggle(isOn: Binding(get: { value > 0.5 }, set: { onChange($0 ? 1 : 0) })) {
                    EmptyView()
                }
                .labelsHidden()
            case .enumType:
                Picker(parameter.label, selection: Binding(get: { Int(value.rounded()) }, set: { onChange(Float($0)) })) {
                    ForEach(Array(parameter.options.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            case .color:
                Slider(value: Binding(get: { value }, set: onChange), in: parameter.minValue...parameter.maxValue)
            }
        }
    }

    private var valueText: String {
        switch parameter.type {
        case .int: return String(Int(value))
        case .bool: return value > 0.5 ? "On" : "Off"
        case .enumType: return parameter.options.indices.contains(Int(value.rounded())) ? parameter.options[Int(value.rounded())] : ""
        default: return String(format: "%.2f", value)
        }
    }
}
