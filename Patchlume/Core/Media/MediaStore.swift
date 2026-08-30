import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MediaKind: String, Codable {
    case photo
    case video
}

/// Copies a picked photo/video into the app's own sandbox so it survives
/// after the system picker's temporary access to it ends, and so it's
/// still there next time a saved patch referencing it loads — same
/// one-file-per-import convention as Modula's `SampleStore` (Documents/Media
/// here instead of Documents/Samples), keyed by a stable UUID filename
/// rather than the original file name.
enum MediaStore {
    static var mediaDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// `ref` is "<uuid>.<ext>" — the extension alone is enough to tell
    /// `kind(forRef:)` and the render engine's video/photo pipeline apart,
    /// no separate metadata file needed.
    static func importPhoto(data: Data, fileExtension: String = "jpg") throws -> String {
        let ref = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: mediaDirectory.appendingPathComponent(ref), options: .atomic)
        return ref
    }

    static func importVideo(from temporaryURL: URL) throws -> String {
        let ref = "\(UUID().uuidString).mov"
        let dest = mediaDirectory.appendingPathComponent(ref)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: temporaryURL, to: dest)
        return ref
    }

    static func url(forRef ref: String) -> URL {
        mediaDirectory.appendingPathComponent(ref)
    }

    static func kind(forRef ref: String) -> MediaKind {
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
        return videoExtensions.contains((ref as NSString).pathExtension.lowercased()) ? .video : .photo
    }
}

/// The recipe Apple documents for receiving a video through `PhotosPicker`:
/// videos arrive as a security-scoped temporary file, not raw `Data`, so
/// `Transferable` has to copy it out to a stable location as part of
/// loading it (the temp file is gone once the picker session ends).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
