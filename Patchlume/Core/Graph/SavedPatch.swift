import Foundation

/// A named, dated snapshot of an entire `Graph` — nodes, cables, macros,
/// everything — persisted as its own file so patches survive an app
/// restart and can be browsed/reloaded. `Graph` itself stays plain
/// (undo/redo snapshots and templates don't need identity or a name); this
/// wraps one only when it's actually being saved.
struct SavedPatch: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var graph: Graph

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), graph: Graph) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.graph = graph
    }
}

/// Reads and writes patches as JSON files under Documents/Patches — same
/// one-file-per-patch pattern Modula's `PatchStore` uses, named by id so
/// re-saving the same patch overwrites its own file instead of piling up
/// duplicates.
enum PatchStore {
    static var patchesDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("Patches", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func url(for patch: SavedPatch) -> URL {
        patchesDirectory.appendingPathComponent("\(patch.id.uuidString).json")
    }

    static func save(_ patch: SavedPatch) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(patch)
        try data.write(to: url(for: patch), options: .atomic)
    }

    static func loadAll() -> [SavedPatch] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: patchesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SavedPatch.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func delete(_ patch: SavedPatch) {
        try? FileManager.default.removeItem(at: url(for: patch))
    }
}
