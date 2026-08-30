import CoreGraphics
import Metal
import MetalKit
import UIKit

/// Per-node texture source for "text" generator nodes. Renders the string
/// as a white-on-transparent alpha mask via Core Graphics — ONLY when the
/// text content or font choice actually changes, not every frame — and
/// caches the result. Palette color and on-screen scale are deliberately
/// left OUT of that CPU render and applied instead in `fs_text` from live
/// uniforms, so riding those with a macro or inline LFO is cheap (just a
/// shader read) instead of re-rasterizing text 60 times a second.
@MainActor
final class TextTextureEngine {
    private let device: MTLDevice

    private struct CacheKey: Equatable {
        let content: String
        let fontIndex: Int
    }
    private var cache: [UUID: (key: CacheKey, texture: MTLTexture)] = [:]

    static let fontNames = ["System", "Rounded", "Serif", "Monospaced", "Bold", "Condensed"]

    init(device: MTLDevice) {
        self.device = device
    }

    /// Called every frame by `RenderEngine` for each "text" generator node.
    func texture(for node: GraphNode) -> MTLTexture? {
        let content = (node.textContent ?? "").isEmpty ? "PATCHLUME" : node.textContent!
        let fontIndex = Int(node.parameters["p2"] ?? 0)
        let key = CacheKey(content: content, fontIndex: fontIndex)
        if let cached = cache[node.id], cached.key == key { return cached.texture }
        guard let texture = render(content: content, fontIndex: fontIndex) else { return cache[node.id]?.texture }
        cache[node.id] = (key, texture)
        return texture
    }

    func pruneStale(keeping nodeIDs: Set<UUID>) {
        for id in cache.keys where !nodeIDs.contains(id) { cache.removeValue(forKey: id) }
    }

    private func font(forIndex index: Int, size: CGFloat) -> UIFont {
        switch index {
        case 1: return .systemFont(ofSize: size, weight: .bold, width: .standard)
            .fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size, weight: .bold)
        case 2: return UIFont(descriptor: UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: size).fontDescriptor, size: size)
        case 3: return .monospacedSystemFont(ofSize: size, weight: .semibold)
        case 4: return .systemFont(ofSize: size, weight: .heavy)
        case 5: return UIFont(descriptor: UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withSymbolicTraits(.traitCondensed) ?? UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor, size: size)
        default: return .systemFont(ofSize: size, weight: .semibold)
        }
    }

    /// Renders `content` at a fixed internal point size (supersampled for
    /// crispness once the shader scales it up/down live), with a trailing
    /// transparent gap equal to a third of the text's own width so the
    /// shader's horizontal-repeat scroll tiles seamlessly instead of
    /// running words together.
    private func render(content: String, fontIndex: Int) -> MTLTexture? {
        let pointSize: CGFloat = 160
        let uiFont = font(forIndex: fontIndex, size: pointSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: uiFont, .foregroundColor: UIColor.white]
        let textSize = (content as NSString).size(withAttributes: attributes)
        guard textSize.width > 0, textSize.height > 0 else { return nil }

        let gap = textSize.width * 0.33
        let canvasSize = CGSize(width: textSize.width + gap, height: textSize.height * 1.2)

        // Drawn straight into a device-RGB CGContext and uploaded to Metal
        // via `replace(region:...)` rather than routed through
        // `UIGraphicsImageRenderer` + `MTKTextureLoader` — that combination
        // silently failed here: the renderer's CGImage comes out in an
        // extended/wide-gamut color space, and `MTKTextureLoader.newTexture`
        // throws (silently swallowed by `try?`) rather than converting it,
        // leaving the "text" generator permanently on the blank fallback
        // texture no matter what the content/font/color were.
        let width = max(Int(canvasSize.width.rounded(.up)), 1)
        let height = max(Int(canvasSize.height.rounded(.up)), 1)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        UIGraphicsPushContext(context)
        // CGContext is bottom-up flipped relative to UIKit's top-down
        // coordinate space that `NSString.draw` expects.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let origin = CGPoint(x: 0, y: (canvasSize.height - textSize.height) / 2)
        (content as NSString).draw(at: origin, withAttributes: attributes)
        UIGraphicsPopContext()

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0, withBytes: &pixels, bytesPerRow: bytesPerRow)
        return texture
    }
}
