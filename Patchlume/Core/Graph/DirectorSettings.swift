import Foundation

/// User-facing constraints on `AutoDirectorEngine` — a handful of
/// high-level knobs, not per-scene micromanagement. Every default here
/// matches the engine's original hardcoded behavior exactly, so a user who
/// never opens the settings sheet sees zero difference from before this
/// existed; only touches the panel change anything.
struct DirectorSettings: Codable, Equatable {
    enum MoodEmphasis: String, Codable, CaseIterable {
        case all, cameraOnly, generativeOnly
    }
    enum Pace: String, Codable, CaseIterable {
        case slow, normal, fast

        /// Scene duration, in seconds — `normal` is the engine's original
        /// 25...50 range.
        var sceneDurationRange: ClosedRange<Double> {
            switch self {
            case .slow: return 45...80
            case .normal: return 25...50
            case .fast: return 12...25
            }
        }
    }

    var moodEmphasis: MoodEmphasis = .all
    var pace: Pace = .normal
    var useNDIWhenConnected = true
    var autoShotChanges = true
    var colorMoodShifts = true

    private static let defaultsKey = "com.dlrk.patchlume.directorSettings"

    static func loadFromDefaults() -> DirectorSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(DirectorSettings.self, from: data) else {
            return DirectorSettings()
        }
        return decoded
    }

    func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
