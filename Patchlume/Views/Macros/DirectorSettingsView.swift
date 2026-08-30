import SwiftUI

/// High-level constraints on `AutoDirectorEngine`, not per-scene
/// micromanagement — mood emphasis, pace, and three opt-outs (NDI,
/// automatic shot changes, color mood shifts). Every default matches the
/// engine's original always-on behavior exactly, so leaving this sheet
/// untouched changes nothing; `AutoDirectorEngine.settings` persists to
/// `UserDefaults` the moment anything here is changed.
struct DirectorSettingsView: View {
    @ObservedObject var autoDirector: AutoDirectorEngine
    @Environment(\.dismiss) private var dismiss

    // Owned local copy, not a binding chained through `autoDirector.settings`
    // (class -> struct -> enum) — that chain visibly reverted edits while
    // the director was inactive (reported on-device), a known-fragile
    // SwiftUI pattern. Seeded on appear, pushed back to `autoDirector`
    // explicitly on every change instead.
    @State private var settings = DirectorSettings()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mood Emphasis", selection: $settings.moodEmphasis) {
                        Text("All").tag(DirectorSettings.MoodEmphasis.all)
                        Text("Camera-Forward").tag(DirectorSettings.MoodEmphasis.cameraOnly)
                        Text("Generative Only").tag(DirectorSettings.MoodEmphasis.generativeOnly)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Which scenes the director is allowed to pick. \u{201C}Camera-Forward\u{201D} includes hybrid scenes that mix the camera with generative visuals; \u{201C}Generative Only\u{201D} keeps the camera off screen entirely.")
                }

                Section {
                    Picker("Pace", selection: $settings.pace) {
                        Text("Slow").tag(DirectorSettings.Pace.slow)
                        Text("Normal").tag(DirectorSettings.Pace.normal)
                        Text("Fast").tag(DirectorSettings.Pace.fast)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("How long each scene stays up before the next transition begins.")
                }

                Section {
                    Toggle("Use NDI When Connected", isOn: $settings.useNDIWhenConnected)
                } footer: {
                    Text("When a second device is connected over NDI, let the director cut to it on its own. Turn off to keep NDI available for you to mix in by hand only.")
                }

                Section {
                    Toggle("Automatic Shot Changes", isOn: $settings.autoShotChanges)
                } footer: {
                    Text("Let the director switch camera lens (and NDI source, if enabled above) on its own. Turn off to keep whatever shot each scene starts with.")
                }

                Section {
                    Toggle("Color Mood Shifts", isOn: $settings.colorMoodShifts)
                } footer: {
                    Text("Let the director drift Saturation macros toward moments of monochrome, oversaturated, or split camera/rest color grading.")
                }
            }
            .navigationTitle("Director Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { settings = autoDirector.settings }
        .onChange(of: settings) { _, newValue in autoDirector.settings = newValue }
    }
}
