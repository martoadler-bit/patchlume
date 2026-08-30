import AVFoundation
import CoreVideo
import Metal
import MetalKit
import UIKit

/// Per-node texture source for "media" generator nodes — unlike the camera
/// (one single global feed), each media node can point at its own
/// different photo or video, so this keys everything by node id rather
/// than being a single shared engine.
///
/// A photo decodes once and is cached as a static texture. A video gets
/// its own looping, muted `AVPlayer` + `AVPlayerItemVideoOutput`, polled
/// once per render frame for whatever pixel buffer is current — same
/// CVMetalTextureCache bridging `CameraCaptureEngine`/`VideoRecorder` use,
/// just going the opposite direction from a file instead of a live camera.
@MainActor
final class MediaTextureEngine {
    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?

    private struct VideoPlayback {
        let player: AVPlayer
        let output: AVPlayerItemVideoOutput
        let ref: String
        let endObserver: NSObjectProtocol
    }

    private var photoTextures: [UUID: (ref: String, texture: MTLTexture)] = [:]
    private var videoPlaybacks: [UUID: VideoPlayback] = [:]
    private var lastVideoTextures: [UUID: MTLTexture] = [:]

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    /// Called every frame by `RenderEngine` for each "media" generator node.
    func texture(for node: GraphNode) -> MTLTexture? {
        guard let ref = node.mediaRef else {
            removePhoto(nodeID: node.id)
            removeVideo(nodeID: node.id)
            return nil
        }
        switch MediaStore.kind(forRef: ref) {
        case .photo:
            removeVideo(nodeID: node.id) // in case this node switched away from a video
            return photoTexture(nodeID: node.id, ref: ref)
        case .video:
            removePhoto(nodeID: node.id)
            return videoTexture(nodeID: node.id, ref: ref)
        }
    }

    /// Drops playback/texture state for any node no longer in the graph —
    /// called from `GraphViewModel` whenever the graph changes, so a
    /// deleted media node's video actually stops instead of quietly
    /// looping forever in the background.
    func pruneStale(keeping nodeIDs: Set<UUID>) {
        for id in photoTextures.keys where !nodeIDs.contains(id) { photoTextures.removeValue(forKey: id) }
        for id in videoPlaybacks.keys where !nodeIDs.contains(id) { removeVideo(nodeID: id) }
    }

    private func photoTexture(nodeID: UUID, ref: String) -> MTLTexture? {
        if let cached = photoTextures[nodeID], cached.ref == ref { return cached.texture }
        let url = MediaStore.url(forRef: ref)
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else { return nil }
        guard let texture = try? MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: [.SRGB: false]) else { return nil }
        photoTextures[nodeID] = (ref, texture)
        return texture
    }

    private func videoTexture(nodeID: UUID, ref: String) -> MTLTexture? {
        if videoPlaybacks[nodeID]?.ref != ref {
            removeVideo(nodeID: nodeID)
            let url = MediaStore.url(forRef: ref)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
            let item = AVPlayerItem(url: url)
            item.add(output)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true // the app's own audio engine drives reactivity, not this
            player.actionAtItemEnd = .none
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
            player.play()
            videoPlaybacks[nodeID] = VideoPlayback(player: player, output: output, ref: ref, endObserver: observer)
        }
        guard let playback = videoPlaybacks[nodeID] else { return nil }

        let itemTime = playback.output.itemTime(forHostTime: CACurrentMediaTime())
        if playback.output.hasNewPixelBuffer(forItemTime: itemTime),
           let pixelBuffer = playback.output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
           let texture = makeTexture(from: pixelBuffer) {
            lastVideoTextures[nodeID] = texture
            return texture
        }
        // No new decoded frame on this particular render tick (video frame
        // rate is usually lower than the render loop's) — reuse whatever
        // was last decoded rather than flashing blank between frames.
        return lastVideoTextures[nodeID]
    }

    private func removePhoto(nodeID: UUID) {
        photoTextures.removeValue(forKey: nodeID)
    }

    private func removeVideo(nodeID: UUID) {
        guard let playback = videoPlaybacks.removeValue(forKey: nodeID) else { return }
        playback.player.pause()
        NotificationCenter.default.removeObserver(playback.endObserver)
        lastVideoTextures.removeValue(forKey: nodeID)
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
}
