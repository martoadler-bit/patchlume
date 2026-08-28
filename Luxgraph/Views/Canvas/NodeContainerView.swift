import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Chrome shared by every node: draggable header, port jacks top/bottom,
/// duplicate/delete menu, a compact knob row for its parameters. Ported
/// from Modula's `ModuleContainerView` (Module -> Node, Patch -> Graph).
struct NodeContainerView: View {
    @EnvironmentObject var store: GraphStore
    @EnvironmentObject var lessonViewModel: LessonViewModel
    let node: GraphNode
    let scale: CGFloat

    @State private var dragOrigin: CGPoint?
    @State private var showingMediaPicker = false
    @State private var mediaPickerItem: PhotosPickerItem?
    @State private var showingTextEditor = false
    @State private var textDraft = ""

    private var ports: (inputs: [PortDescriptor], outputs: [PortDescriptor]) {
        NodeCatalog.ports(kind: node.kind)
    }
    private var parameters: [ParameterDescriptor] {
        NodeCatalog.parameters(kind: node.kind, subtype: node.subtype)
    }
    private var isSelected: Bool { store.selectedNodeID == node.id }
    private var cardWidth: CGFloat { NodeLayoutMetrics.width(for: node.kind) }
    private var familyColor: Color { NodeFamily.of(node.kind).color }

    // When a step knows the exact instance (graph tours), match on id so
    // duplicate-kind nodes (two generators, say) don't all glow at once;
    // hand-written lessons fall back to kind (+ optional subtype).
    private var isLessonHighlighted: Bool {
        if let focusID = lessonViewModel.focusNodeID {
            return focusID == node.id
        }
        guard let kind = lessonViewModel.highlightedKind, kind == node.kind else { return false }
        if let subtype = lessonViewModel.highlightedSubtype {
            return subtype == node.subtype
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            VStack(spacing: 10) {
                if !ports.inputs.isEmpty {
                    portsRow(ports.inputs, direction: .input)
                }
                nodeContent
                if !ports.outputs.isEmpty {
                    portsRow(ports.outputs, direction: .output)
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isLessonHighlighted ? Color.yellow : (isSelected ? Color.accentColor : familyColor.opacity(0.55)),
                    lineWidth: isLessonHighlighted ? 3 : (isSelected ? 2 : 1.5)
                )
        )
        .shadow(color: isLessonHighlighted ? Color.yellow.opacity(0.6) : .black.opacity(0.45), radius: isLessonHighlighted ? 14 : 10, y: 5)
        .position(node.position)
        .onTapGesture { store.selectedNodeID = node.id }
        .photosPicker(isPresented: $showingMediaPicker, selection: $mediaPickerItem, matching: .any(of: [.images, .videos]))
        .onChange(of: mediaPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPickedMedia(newItem) }
        }
        .alert("Text", isPresented: $showingTextEditor) {
            TextField("Text", text: $textDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.setTextContent(nodeID: node.id, text: textDraft) }
        }
    }

    @MainActor
    private func importPickedMedia(_ item: PhotosPickerItem) async {
        defer { mediaPickerItem = nil }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self),
                  let ref = try? MediaStore.importVideo(from: movie.url) else { return }
            store.setMediaRef(nodeID: node.id, ref: ref)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            guard let ref = try? MediaStore.importPhoto(data: data, fileExtension: ext) else { return }
            store.setMediaRef(nodeID: node.id, ref: ref)
        }
    }

    private var header: some View {
        HStack {
            Circle().fill(familyColor).frame(width: 7, height: 7)
            Text(NodeCatalog.displayName(kind: node.kind, subtype: node.subtype))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Menu {
                if node.kind == .generator, node.subtype == "media" {
                    Button {
                        showingMediaPicker = true
                    } label: {
                        Label("Choose Photo/Video", systemImage: "photo.on.rectangle")
                    }
                }
                Button {
                    store.duplicateNode(id: node.id)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) {
                    store.disconnectAll(forNodeID: node.id)
                } label: {
                    Label("Disconnect All Cables", systemImage: "bolt.slash")
                }
                .disabled(!store.hasAnyConnections(nodeID: node.id))
                Button(role: .destructive) {
                    store.removeNode(id: node.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(coordinateSpace: .named("canvas"))
                .onChanged { value in
                    if dragOrigin == nil { dragOrigin = node.position }
                    guard let origin = dragOrigin else { return }
                    let newPosition = CGPoint(
                        x: origin.x + value.translation.width / scale,
                        y: origin.y + value.translation.height / scale
                    )
                    store.updatePosition(id: node.id, position: newPosition)
                }
                .onEnded { _ in dragOrigin = nil }
        )
    }

    private func portsRow(_ ports: [PortDescriptor], direction: PortDirection) -> some View {
        HStack(spacing: 14) {
            ForEach(ports) { port in
                VStack(spacing: 2) {
                    if direction == .output {
                        Text(port.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    PortView(nodeID: node.id, port: port, direction: direction)
                    if direction == .input {
                        Text(port.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var nodeContent: some View {
        if node.kind == .generator, node.subtype == "text" {
            Button {
                textDraft = node.textContent ?? ""
                showingTextEditor = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "textformat")
                    Text((node.textContent?.isEmpty == false ? node.textContent! : "LUXGRAPH"))
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        if parameters.isEmpty {
            Text(node.kind == .output ? "Final composite" : "No parameters")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                ForEach(parameters) { parameter in
                    if parameter.type == .enumType {
                        enumParameterView(parameter)
                    } else {
                        KnobView(
                            label: parameter.label,
                            parameter: parameter,
                            value: node.parameters[parameter.id] ?? parameter.defaultValue,
                            onChange: { store.updateParameter(nodeID: node.id, paramID: parameter.id, value: $0) },
                            modulator: node.paramModulators[parameter.id],
                            onModulatorChange: { store.setParamModulator(nodeID: node.id, paramID: parameter.id, modulator: $0) }
                        )
                    }
                }
            }
        }
    }

    private func enumParameterView(_ parameter: ParameterDescriptor) -> some View {
        let currentIndex = Int((node.parameters[parameter.id] ?? parameter.defaultValue).rounded())
        return VStack(spacing: 4) {
            Text(parameter.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Menu {
                ForEach(Array(parameter.options.enumerated()), id: \.offset) { index, name in
                    Button(name) {
                        store.updateParameter(nodeID: node.id, paramID: parameter.id, value: Float(index))
                    }
                }
            } label: {
                Text(parameter.options.indices.contains(currentIndex) ? parameter.options[currentIndex] : "—")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.2)))
            }
        }
    }
}

/// One jack. Drag from an output port and release over a compatible input
/// port to connect; long-press a port to disconnect whatever's plugged into
/// it (the reliable fallback path when tapping the thin cable itself isn't
/// convenient).
struct PortView: View {
    @EnvironmentObject var canvasState: CanvasInteractionState
    @EnvironmentObject var store: GraphStore
    let nodeID: UUID
    let port: PortDescriptor
    let direction: PortDirection

    private var key: PortKey { PortKey(nodeID: nodeID, portID: port.id, direction: direction) }

    var body: some View {
        Circle()
            .fill(portColor(for: port.signalType))
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .anchorPreference(key: PortAnchorsKey.self, value: .center) { [key: $0] }
            .contentShape(Circle().inset(by: -10))
            // Long-press-to-disconnect and drag-to-connect composed via
            // `.exclusively(before:)` — two separately-stacked gesture
            // modifiers here could let a held-then-moved touch fire the
            // long-press disconnect AND still let the drag continue as a
            // new connect, silently severing an existing cable with no
            // indication that's what just happened. `.exclusively`
            // guarantees a touch commits to one or the other, never both.
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        store.disconnect(portKey: key)
                    }
                    .exclusively(before:
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                if canvasState.pendingCable == nil {
                                    canvasState.pendingCable = PendingCable(origin: key, signalType: port.signalType, currentPoint: value.location)
                                } else {
                                    canvasState.pendingCable?.currentPoint = value.location
                                }
                            }
                            .onEnded { value in
                                defer { canvasState.pendingCable = nil }
                                guard let target = canvasState.nearestPort(to: value.location, excluding: key) else { return }
                                if direction == .output {
                                    store.connect(source: key, dest: target)
                                } else {
                                    store.connect(source: target, dest: key)
                                }
                            }
                    )
            )
    }
}
