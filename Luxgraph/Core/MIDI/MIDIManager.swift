import CoreMIDI
import Foundation

/// Listens to every available Core MIDI source (USB, Bluetooth, virtual) and
/// exposes the latest 0...1 value of every CC and note-on velocity seen, so
/// `MIDI CC`/`MIDI Note` input nodes can read them each frame. Direct port
/// of Modula's `MIDIManager` packet-walking approach, renamed for Luxgraph.
@MainActor
final class MIDIManager: ObservableObject {
    @Published private(set) var connectedSourceNames: [String] = []
    @Published private(set) var ccValues: [Int: Float] = [:]
    @Published private(set) var noteValues: [Int: Float] = [:]

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    init() {
        setUpCoreMIDI()
    }

    private func setUpCoreMIDI() {
        let clientStatus = MIDIClientCreateWithBlock("LuxgraphMIDIClient" as CFString, &client) { [weak self] _ in
            Task { @MainActor in
                self?.connectAllSources()
            }
        }
        guard clientStatus == noErr else { return }

        let portStatus = MIDIInputPortCreateWithBlock(client, "LuxgraphInputPort" as CFString, &inputPort) { [weak self] packetList, _ in
            let bytes = MIDIManager.bytes(from: packetList)
            Task { @MainActor in
                self?.handle(bytes: bytes)
            }
        }
        guard portStatus == noErr else { return }

        connectAllSources()
    }

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var names: [String] = []
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(inputPort, source, nil)
            if let name = Self.name(of: source) {
                names.append(name)
            }
        }
        connectedSourceNames = names
    }

    private static func name(of endpoint: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let cfName = unmanagedName?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    /// Flattens every packet's bytes off the real-time MIDI thread. Walks
    /// the packet list via a pointer into the list's own buffer rather than
    /// copying each packet into a local variable first — `MIDIPacketNext`
    /// computes the next packet's address from wherever you hand it, so
    /// stepping from a stack copy silently breaks on any packet list with
    /// more than one packet in it.
    private nonisolated static func bytes(from packetList: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
            var packetPointer = firstPacket
            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let byteCount = Int(packet.length)
                let bytes = withUnsafeBytes(of: packet.data) { raw -> [UInt8] in
                    Array(raw.prefix(byteCount))
                }
                messages.append(bytes)
                packetPointer = UnsafePointer(MIDIPacketNext(packetPointer))
            }
        }
        return messages
    }

    private func handle(bytes messages: [[UInt8]]) {
        for bytes in messages {
            guard bytes.count >= 2 else { continue }
            let status = bytes[0] & 0xF0

            if status == 0xB0, bytes.count >= 3 {
                let cc = Int(bytes[1])
                let value = Float(bytes[2]) / 127.0
                ccValues[cc] = value
            } else if status == 0x90, bytes.count >= 3 {
                let note = Int(bytes[1])
                let velocity = Float(bytes[2]) / 127.0
                noteValues[note] = velocity > 0 ? velocity : 0
            } else if status == 0x80, bytes.count >= 2 {
                let note = Int(bytes[1])
                noteValues[note] = 0
            }
        }
    }

    func value(forCC cc: Int) -> Float { ccValues[cc] ?? 0 }
    func latestActiveNoteValue() -> Float { noteValues.values.max() ?? 0 }
}
