import SwiftUI

/// List of NDI sources currently visible on the local network — a second
/// phone running the free "NDI Camera" app, another Patchlume, OBS,
/// Resolume. Tapping one connects `NDISourceEngine` (a single global
/// receiver, same "one at a time" scope as the local camera) and closes.
struct NDISourcePickerView: View {
    @ObservedObject var engine: NDISourceEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if engine.availableSources.isEmpty {
                    Text("No NDI sources found on this network yet. Make sure the other device is on the same Wi-Fi and broadcasting (e.g. the free \u{201C}NDI Camera\u{201D} app), then Refresh.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(engine.availableSources, id: \.self) { name in
                    Button {
                        engine.connect(toSourceNamed: name)
                        dismiss()
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if engine.currentSourceName == name {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                    }
                }
                if engine.isConnected {
                    Button(role: .destructive) {
                        engine.disconnect()
                        dismiss()
                    } label: {
                        Label("Disconnect", systemImage: "antenna.radiowaves.left.and.right.slash")
                    }
                }
            }
            .navigationTitle("NDI Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        engine.refreshSources()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { engine.refreshSources() }
        }
    }
}
