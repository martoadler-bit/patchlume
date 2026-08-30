import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd

/// Drives the Metal render plan built fresh from the current graph every
/// frame: generator pass -> modifier/combiner passes chained over offscreen
/// MTLTextures -> present pass into the MTKView's drawable. Each texture-
/// producing node gets its own ping-pong pair of offscreen textures so a
/// "feedback" modifier can read its own previous frame's output without
/// racing the pass that's currently writing into it.
@MainActor
final class RenderEngine: NSObject, MTKViewDelegate {
    /// Not private: every `MTKView` this engine drives (main preview,
    /// fullscreen, external display) needs to be handed THIS exact device
    /// rather than calling `MTLCreateSystemDefaultDevice()` again itself —
    /// on a single-GPU iPhone that call is expected to keep returning an
    /// equivalent device, but there's no hard guarantee of that once a
    /// second physical display is actually in the picture, and command
    /// buffers/textures built against one device are not usable with
    /// another. Sharing one device explicitly removes the question.
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private var presentPipeline: MTLRenderPipelineState?

    private struct PingPong {
        var a: MTLTexture
        var b: MTLTexture
        var currentIsA: Bool = true
    }
    private var nodeTextures: [UUID: PingPong] = [:]
    private var blankTexture: MTLTexture?
    private var workingSize = CGSize(width: 960, height: 540)

    /// Supplied by the owning view model each frame.
    var graphProvider: (() -> Graph)?
    var frameContextProvider: (() -> FrameContext)?
    var inputValueProvider: ((GraphNode, FrameContext) -> Float)?
    /// Resolves a node's parameters AFTER inline per-parameter LFOs and any
    /// Macro assignments are folded in — the base `node.parameters` values
    /// plus all of that live movement, clamped back into each parameter's
    /// declared range. Falls back to the raw stored values if unset.
    var resolvedParameterProvider: ((GraphNode, FrameContext) -> [String: Float])?
    /// The "camera" generator's live frame, from `CameraCaptureEngine`. Nil
    /// while the camera isn't running/authorized — falls back to a blank
    /// black texture so the pass always has something valid to sample.
    var cameraTextureProvider: (() -> MTLTexture?)?
    var mediaTextureProvider: ((GraphNode) -> MTLTexture?)?
    var textTextureProvider: ((GraphNode) -> MTLTexture?)?
    var ndiSourceTextureProvider: (() -> MTLTexture?)?
    /// Set once by `GraphViewModel`. Recording is driven by `VideoRecorder`'s
    /// own timer calling `captureFrameForRecording()` — entirely decoupled
    /// from the MTKView draw loop, so it captures exactly once per encoded
    /// frame regardless of how many preview surfaces (main, fullscreen,
    /// external display) happen to be actively drawing at the same time.
    var videoRecorder: VideoRecorder?
    var ndiOutputManager: NDIOutputManager?

    /// The fixed resolution every node's offscreen texture renders at —
    /// exposed so `VideoRecorder` can size its pixel buffer pool to match
    /// exactly (no scaling needed, and the recorded video's aspect matches
    /// what the working buffer itself actually is, before any cover-fit
    /// cropping a *display* target would apply).
    var recordingResolution: CGSize { workingSize }

    struct FrameContext {
        var time: Float = 0
        var beat: Float = 0
        var beatStrength: Float = 0
        var bass: Float = 0
        var mid: Float = 0
        var treble: Float = 0
        var energy: Float = 0
        /// Largest-first, up to 3 — see `Uniforms.faceCount`/`face0...2`.
        var faceBoxes: [CGRect] = []
    }

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Patchlume requires a Metal-capable device.")
        }
        self.device = device
        self.commandQueue = queue
        super.init()
        buildPipelines()
    }

    private func fragmentFunctionName(kind: NodeKind, subtype: String) -> String {
        switch kind {
        case .generator: return "fs_" + subtype
        case .modifier: return "fs_" + subtype
        case .combiner: return "fs_" + subtype
        case .output, .input: return "fs_blank"
        }
    }

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else { return }
        guard let vertexFunction = library.makeFunction(name: "vs_main") else { return }

        func makePipeline(fragmentName: String, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
            guard let fragmentFunction = library.makeFunction(name: fragmentName) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        var names = NodeCatalog.generatorTypes.map { "fs_" + $0 }
        names += NodeCatalog.modifierTypes.map { "fs_" + $0 }
        names += NodeCatalog.combinerTypes.map { "fs_" + $0 }
        names.append("fs_blank")
        for name in names {
            if let pipeline = makePipeline(fragmentName: name, pixelFormat: .bgra8Unorm) {
                pipelines[name] = pipeline
            }
        }
        presentPipeline = makePipeline(fragmentName: "fs_present", pixelFormat: .bgra8Unorm)

        let blankDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        blankDescriptor.usage = [.shaderRead]
        blankTexture = device.makeTexture(descriptor: blankDescriptor)
    }

    private func makeTexture() -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, Int(workingSize.width)),
            height: max(1, Int(workingSize.height)),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("Patchlume: failed to allocate an offscreen render texture.")
        }
        return texture
    }

    private func pingPong(for nodeID: UUID) -> PingPong {
        if let existing = nodeTextures[nodeID] { return existing }
        let created = PingPong(a: makeTexture(), b: makeTexture())
        nodeTextures[nodeID] = created
        return created
    }

    /// The texture holding this node's most recently completed render.
    private func readTexture(for nodeID: UUID) -> MTLTexture {
        let pair = pingPong(for: nodeID)
        return pair.currentIsA ? pair.a : pair.b
    }

    private func writeTexture(for nodeID: UUID) -> MTLTexture {
        let pair = pingPong(for: nodeID)
        return pair.currentIsA ? pair.b : pair.a
    }

    private func commitWrite(for nodeID: UUID) {
        nodeTextures[nodeID]?.currentIsA.toggle()
    }

    // MARK: - MTKViewDelegate

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            renderFrame(in: view)
        }
    }

    private func renderFrame(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let graphProvider, let frameContextProvider,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let graph = graphProvider()
        let context = frameContextProvider()
        let order = graph.renderOrder()

        for node in order where node.kind == .generator || node.kind == .modifier || node.kind == .combiner {
            render(node: node, graph: graph, context: context, commandBuffer: commandBuffer)
        }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        if let output = order.first(where: { $0.kind == .output }),
           let sourceID = graph.textureSources(into: output.id)["in"],
           let pipeline = presentPipeline {
            encoder.setRenderPipelineState(pipeline)
            var coverScale = coverFitScale(drawableSize: view.drawableSize)
            encoder.setFragmentBytes(&coverScale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            encoder.setFragmentTexture(readTexture(for: sourceID), index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Renders the current graph state once, independent of any MTKView,
    /// and hands the composited result to whichever off-screen consumers
    /// are currently active — `videoRecorder` (file export) and/or
    /// `ndiOutputManager` (live network output). Called by each
    /// consumer's own fixed-rate capture timer (they each run
    /// independently, so this can fire from either one, or both, without
    /// rendering the graph twice for the same tick's worth of work being
    /// wasted — each call is just a fresh, cheap, consistent snapshot).
    func captureFrameForRecording() {
        let isRecording = videoRecorder?.isRecording ?? false
        let isStreamingNDI = ndiOutputManager?.isActive ?? false
        guard isRecording || isStreamingNDI,
              let graphProvider, let frameContextProvider,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let graph = graphProvider()
        let context = frameContextProvider()
        let order = graph.renderOrder()

        for node in order where node.kind == .generator || node.kind == .modifier || node.kind == .combiner {
            render(node: node, graph: graph, context: context, commandBuffer: commandBuffer)
        }

        guard let output = order.first(where: { $0.kind == .output }),
              let sourceID = graph.textureSources(into: output.id)["in"] else {
            commandBuffer.commit()
            return
        }
        let texture = readTexture(for: sourceID)
        if isRecording {
            videoRecorder?.appendFrame(texture: texture, commandBuffer: commandBuffer)
        }
        if isStreamingNDI {
            ndiOutputManager?.appendFrame(texture: texture, commandBuffer: commandBuffer)
        }
        commandBuffer.commit()
    }

    // "Cover" fit (crop, never distort) between the fixed working buffer
    // (always 16:9-ish, `workingSize`) and whatever the live drawable's
    // aspect actually is — a wide preview strip crops top/bottom, a tall
    // fullscreen portrait view crops the sides, either way the image keeps
    // its real proportions.
    private func coverFitScale(drawableSize: CGSize) -> SIMD2<Float> {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return SIMD2<Float>(1, 1) }
        let srcAspect = Float(workingSize.width / workingSize.height)
        let dstAspect = Float(drawableSize.width / drawableSize.height)
        if dstAspect >= srcAspect {
            return SIMD2<Float>(1, srcAspect / dstAspect)
        } else {
            return SIMD2<Float>(dstAspect / srcAspect, 1)
        }
    }

    private func render(node: GraphNode, graph: Graph, context: FrameContext, commandBuffer: MTLCommandBuffer) {
        let functionName = fragmentFunctionName(kind: node.kind, subtype: node.subtype)
        guard let pipeline = pipelines[functionName] else { return }

        let target = writeTexture(for: node.id)
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = target
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(pipeline)

        // Camera's own texture is fetched here (not down in the switch
        // below) because fs_camera needs its cover-fit scale — computed
        // from the camera frame's actual aspect vs. the working buffer's —
        // written into the uniforms buffer, which has to happen before
        // `setFragmentBytes` further down.
        let cameraTex: MTLTexture? = (node.kind == .generator && node.subtype == "camera")
            ? (cameraTextureProvider?() ?? blankTexture) : nil
        let mediaTex: MTLTexture? = (node.kind == .generator && node.subtype == "media")
            ? (mediaTextureProvider?(node) ?? blankTexture) : nil
        let textTex: MTLTexture? = (node.kind == .generator && node.subtype == "text")
            ? (textTextureProvider?(node) ?? blankTexture) : nil
        let ndiTex: MTLTexture? = (node.kind == .generator && node.subtype == "ndiSource")
            ? (ndiSourceTextureProvider?() ?? blankTexture) : nil

        var uniforms = Uniforms()
        uniforms.time = context.time
        uniforms.beat = context.beat
        uniforms.beatStrength = context.beatStrength
        uniforms.bass = context.bass
        uniforms.mid = context.mid
        uniforms.treble = context.treble
        uniforms.energy = context.energy
        uniforms.resolution = SIMD2<Float>(Float(workingSize.width), Float(workingSize.height))
        uniforms.faceCount = Float(context.faceBoxes.count)
        // `context.faceBoxes` (from `CameraCaptureEngine.faceBoxes`) is
        // already fully corrected for device orientation and lens — see
        // `CameraCaptureEngine.correctedFaceBox`. No further transform here.
        let faceUniforms: [SIMD4<Float>] = context.faceBoxes.prefix(3).map { box in
            SIMD4<Float>(Float(box.midX), Float(box.midY), Float(box.width / 2), Float(box.height / 2))
        }
        if faceUniforms.count > 0 { uniforms.face0 = faceUniforms[0] }
        if faceUniforms.count > 1 { uniforms.face1 = faceUniforms[1] }
        if faceUniforms.count > 2 { uniforms.face2 = faceUniforms[2] }
        let resolved = resolvedParameterProvider?(node, context) ?? node.parameters
        uniforms.p0 = resolved["p0"] ?? 0
        uniforms.p1 = resolved["p1"] ?? 0
        uniforms.p2 = resolved["p2"] ?? 1
        uniforms.p3 = resolved["p3"] ?? 0
        // Camera doesn't declare p2/p3 as real parameters (NodeCatalog only
        // gives it Exposure/Saturation) — reused here to carry the same
        // "cover" crop scale the final present pass uses, so a portrait
        // camera frame fills the 16:9-ish working buffer by cropping
        // instead of squashing to fit.
        if node.subtype == "camera", let cameraTex, cameraTex.width > 0, cameraTex.height > 0 {
            let camAspect = Float(cameraTex.width) / Float(cameraTex.height)
            let bufAspect = Float(workingSize.width / workingSize.height)
            if bufAspect >= camAspect {
                uniforms.p2 = 1
                uniforms.p3 = camAspect / bufAspect
            } else {
                uniforms.p2 = bufAspect / camAspect
                uniforms.p3 = 1
            }
        }
        // Same cover-fit trick as camera above — "media" only declares
        // Exposure/Saturation, so p2/p3 are free to carry the crop scale
        // computed from the actual imported photo/video's aspect ratio.
        if node.subtype == "media", let mediaTex, mediaTex.width > 0, mediaTex.height > 0 {
            let mediaAspect = Float(mediaTex.width) / Float(mediaTex.height)
            let bufAspect = Float(workingSize.width / workingSize.height)
            if bufAspect >= mediaAspect {
                uniforms.p2 = 1
                uniforms.p3 = mediaAspect / bufAspect
            } else {
                uniforms.p2 = bufAspect / mediaAspect
                uniforms.p3 = 1
            }
        }
        // Same cover-fit trick again — the NDI source's resolution is
        // whatever the sending device chose and can change frame to frame.
        if node.subtype == "ndiSource", let ndiTex, ndiTex.width > 0, ndiTex.height > 0 {
            let ndiAspect = Float(ndiTex.width) / Float(ndiTex.height)
            let bufAspect = Float(workingSize.width / workingSize.height)
            if bufAspect >= ndiAspect {
                uniforms.p2 = 1
                uniforms.p3 = ndiAspect / bufAspect
            } else {
                uniforms.p2 = bufAspect / ndiAspect
                uniforms.p3 = 1
            }
        }
        if let modSource = graph.modulationSource(for: node.id), let inputValueProvider {
            uniforms.modValue = inputValueProvider(modSource, context)
        }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)

        switch node.kind {
        case .modifier:
            let sourceID = graph.textureSources(into: node.id)["in"]
            let sourceTexture = sourceID.map { readTexture(for: $0) } ?? (blankTexture ?? target)
            encoder.setFragmentTexture(sourceTexture, index: 0)
            if node.subtype == "feedback" || node.subtype == "trails" || node.subtype == "lightOrb" || node.subtype == "spotlight" || node.subtype == "faceSpotlight" {
                encoder.setFragmentTexture(readTexture(for: node.id), index: 1)
            }
        case .combiner:
            let sources = graph.textureSources(into: node.id)
            let a = sources["inA"].map { readTexture(for: $0) } ?? (blankTexture ?? target)
            let b = sources["inB"].map { readTexture(for: $0) } ?? (blankTexture ?? target)
            encoder.setFragmentTexture(a, index: 0)
            encoder.setFragmentTexture(b, index: 1)
        case .generator:
            // The two self/external-source generators need something bound
            // at texture(0); every other generator's fragment function
            // takes no texture argument, so binding is simply ignored.
            if node.subtype == "reaction" {
                encoder.setFragmentTexture(readTexture(for: node.id), index: 0)
            } else if node.subtype == "camera" {
                encoder.setFragmentTexture(cameraTex ?? blankTexture, index: 0)
            } else if node.subtype == "media" {
                encoder.setFragmentTexture(mediaTex ?? blankTexture, index: 0)
            } else if node.subtype == "text" {
                encoder.setFragmentTexture(textTex ?? blankTexture, index: 0)
            } else if node.subtype == "ndiSource" {
                encoder.setFragmentTexture(ndiTex ?? blankTexture, index: 0)
            }
        case .input, .output:
            break
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commitWrite(for: node.id)
    }
}
