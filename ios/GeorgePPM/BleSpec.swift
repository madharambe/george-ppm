import Foundation

/// The BLE contract, shared with the ESP32 firmware (firmware/ble_link.py).
///
/// Deliberately Foundation-only: this compiles and is unit-testable on any
/// platform (see tools/swift_harness.cmd), and tools/ios_preflight.py asserts
/// these strings still match the firmware. A drift here would compile cleanly
/// and simply never discover the device.
enum BleSpec {
    static let deviceName = "GeorgePPM"

    static let serviceUUID = "4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6"
    static let telemetryUUID = "4a5b6c7d-0002-4d8e-9f00-a1b2c3d4e5f6"
    static let commandUUID = "4a5b6c7d-0003-4d8e-9f00-a1b2c3d4e5f6"

    /// Firmware negotiates 247; iOS cannot request an MTU, CoreBluetooth
    /// negotiates on its own (~185 payload), which still fits the frame.
    static let targetMTU = 247

    static let commandReset = "RESET"
    static let commandZero = "ZERO"

    /// A 128-bit UUID string is 8-4-4-4-12 hex digits with hyphens.
    static func isWellFormed(_ uuid: String) -> Bool {
        let groups = uuid.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == 5 else { return false }
        let want = [8, 4, 4, 4, 12]
        for (g, w) in zip(groups, want) where g.count != w { return false }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return uuid.unicodeScalars.allSatisfy { $0 == "-" || hex.contains($0) }
    }
}

/// Connection state, extracted from the CoreBluetooth layer so it can be
/// exercised without Apple frameworks.
enum LinkState: Equatable {
    case idle
    case bluetoothOff
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Short label for the status chip.
    var label: String {
        switch self {
        case .idle: return "Idle"
        case .bluetoothOff: return "Bluetooth off"
        case .scanning: return "Scanning..."
        case .connecting(let name): return "Connecting " + name
        case .connected(let name): return "Connected - " + name
        case .failed(let why): return "Failed: " + why
        }
    }
}
