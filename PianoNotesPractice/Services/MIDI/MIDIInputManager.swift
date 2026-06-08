import CoreMIDI
import Foundation
import Observation

/// Monitors external MIDI input devices and forwards note-on events to the quiz.
@Observable
final class MIDIInputManager: @unchecked Sendable {
    private(set) var isDeviceConnected = false
    private(set) var receivedNoteNumber: UInt8?
    @ObservationIgnored private var noteEventsContinuation: AsyncStream<UInt8>.Continuation?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceIDs = Set<MIDIUniqueID>()

    init() {
        configureClient()
        refreshSources()
        AppLog.midi.info("MIDI input manager initialized")
    }

    deinit {
        AppLog.midi.info("MIDI input manager deinitializing")
        disconnectSources()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }

        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    /// Provides note-on events without exposing callback-thread state to SwiftUI.
    func noteEvents() -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            noteEventsContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.noteEventsContinuation = nil
            }
        }
    }

    private func configureClient() {
        let status = MIDIClientCreateWithBlock("Piano Notes Practice MIDI Client" as CFString, &client) { [weak self] notificationPointer in
            self?.handleMIDINotification(notificationPointer.pointee)
        }

        guard status == noErr else {
            AppLog.midi.error("MIDI client creation failed with status \(status, privacy: .public)")
            client = 0
            return
        }

        AppLog.midi.info("MIDI client created")

        let inputStatus = MIDIInputPortCreateWithBlock(client, "Piano Notes Practice MIDI Input" as CFString, &inputPort) { [weak self] packetListPointer, _ in
            self?.handlePacketList(packetListPointer)
        }

        guard inputStatus == noErr else {
            AppLog.midi.error("MIDI input port creation failed with status \(inputStatus, privacy: .public)")
            if client != 0 {
                MIDIClientDispose(client)
            }

            client = 0
            inputPort = 0
            return
        }

        AppLog.midi.info("MIDI input port created")
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        switch notification.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged, .msgSetupChanged:
            AppLog.midi.info("MIDI setup notification received: \(String(describing: notification.messageID), privacy: .public)")
            refreshSources()
        default:
            break
        }
    }

    private func refreshSources() {
        guard client != 0, inputPort != 0 else {
            AppLog.midi.warning("MIDI source refresh skipped because the client or input port is unavailable")
            publishConnectionState(isConnected: false)
            return
        }

        let sourceCount = MIDIGetNumberOfSources()
        AppLog.midi.info("Refreshing MIDI sources; CoreMIDI source count is \(sourceCount, privacy: .public)")
        var availableSources: [(endpoint: MIDIEndpointRef, uniqueID: MIDIUniqueID)] = []

        for sourceIndex in 0..<sourceCount {
            let endpoint = MIDIGetSource(sourceIndex)
            guard endpoint != 0 else { continue }
            guard isEligibleHardwareSource(endpoint) else { continue }

            var isOffline: Int32 = 0
            if MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &isOffline) == noErr, isOffline != 0 {
                continue
            }

            var uniqueID: MIDIUniqueID = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else {
                continue
            }

            availableSources.append((endpoint, uniqueID))
        }

        let nextSourceIDs = Set(availableSources.map(\.uniqueID))
        let removedSourceIDs = connectedSourceIDs.subtracting(nextSourceIDs)
        let addedSourceCount = nextSourceIDs.subtracting(connectedSourceIDs).count
        let wasConnected = !connectedSourceIDs.isEmpty

        AppLog.midi.info(
            "MIDI refresh found \(availableSources.count, privacy: .public) eligible hardware sources; added \(addedSourceCount, privacy: .public), removed \(removedSourceIDs.count, privacy: .public)"
        )

        for removedID in removedSourceIDs {
            if let endpoint = sourceEndpoint(for: removedID) {
                let disconnectStatus = MIDIPortDisconnectSource(inputPort, endpoint)
                if disconnectStatus != noErr {
                    AppLog.midi.error("MIDI source disconnect failed with status \(disconnectStatus, privacy: .public)")
                }
            }
        }

        for source in availableSources where !connectedSourceIDs.contains(source.uniqueID) {
            let connectStatus = MIDIPortConnectSource(inputPort, source.endpoint, nil)
            if connectStatus != noErr {
                AppLog.midi.error("MIDI source connect failed with status \(connectStatus, privacy: .public)")
            }
        }

        connectedSourceIDs = nextSourceIDs
        AppLog.midi.info("MIDI hardware source count is \(self.connectedSourceIDs.count, privacy: .public)")
        if wasConnected != !connectedSourceIDs.isEmpty {
            AppLog.midi.info("MIDI connection active changed to \((!self.connectedSourceIDs.isEmpty), privacy: .public)")
        }
        publishConnectionState(isConnected: !connectedSourceIDs.isEmpty)
    }

    private func disconnectSources() {
        guard inputPort != 0 else { return }

        AppLog.midi.info("Disconnecting \(self.connectedSourceIDs.count, privacy: .public) MIDI sources")

        for sourceID in connectedSourceIDs {
            if let endpoint = sourceEndpoint(for: sourceID) {
                let disconnectStatus = MIDIPortDisconnectSource(inputPort, endpoint)
                if disconnectStatus != noErr {
                    AppLog.midi.error("MIDI source disconnect during cleanup failed with status \(disconnectStatus, privacy: .public)")
                }
            }
        }

        connectedSourceIDs.removeAll()
    }

    private func isEligibleHardwareSource(_ endpoint: MIDIEndpointRef) -> Bool {
        var entity = MIDIEntityRef()
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 else {
            return false
        }

        var device = MIDIDeviceRef()
        guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else {
            return false
        }

        let metadata = [
            stringProperty(kMIDIPropertyDriverOwner, for: device),
            stringProperty(kMIDIPropertyDisplayName, for: endpoint),
            stringProperty(kMIDIPropertyName, for: endpoint),
            stringProperty(kMIDIPropertyName, for: device),
            stringProperty(kMIDIPropertyManufacturer, for: device),
            stringProperty(kMIDIPropertyModel, for: device)
        ]
            .compactMap { $0?.lowercased() }

        let excludedMarkers = [
            "network",
            "session",
            "bluetooth",
            "virtual",
            "inter-app"
        ]

        return !metadata.contains { value in
            excludedMarkers.contains { value.contains($0) }
        }
    }

    private func stringProperty(_ property: CFString, for object: MIDIObjectRef) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &value) == noErr else {
            return nil
        }

        return value?.takeRetainedValue() as String?
    }

    private func sourceEndpoint(for uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        let sourceCount = MIDIGetNumberOfSources()

        for sourceIndex in 0..<sourceCount {
            let endpoint = MIDIGetSource(sourceIndex)
            guard endpoint != 0 else { continue }

            var endpointUniqueID: MIDIUniqueID = 0
            guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &endpointUniqueID) == noErr else {
                continue
            }

            if endpointUniqueID == uniqueID {
                return endpoint
            }
        }

        return nil
    }

    private func handlePacketList(_ packetListPointer: UnsafePointer<MIDIPacketList>) {
        var packet = packetListPointer.pointee.packet

        for packetIndex in 0..<packetListPointer.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(Int(packet.length)))
            }

            processMIDIBytes(bytes)

            if packetIndex < packetListPointer.pointee.numPackets - 1 {
                packet = MIDIPacketNext(&packet).pointee
            }
        }
    }

    private func processMIDIBytes(_ bytes: [UInt8]) {
        var index = 0

        while index + 2 < bytes.count {
            let status = bytes[index]
            let messageType = status & 0xF0

            guard status & 0x80 != 0 else {
                index += 1
                continue
            }

            if messageType == 0x90 {
                let noteNumber = bytes[index + 1]
                let velocity = bytes[index + 2]

                if velocity > 0 {
                    publishReceivedNoteNumber(noteNumber)
                }
            }

            index += 3
        }
    }

    private func publishConnectionState(isConnected: Bool) {
        Task { @MainActor in
            self.isDeviceConnected = isConnected
        }
    }

    private func publishReceivedNoteNumber(_ noteNumber: UInt8) {
        Task { @MainActor in
            self.receivedNoteNumber = noteNumber
            self.noteEventsContinuation?.yield(noteNumber)
        }
    }
}
