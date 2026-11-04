import Foundation

/// Everything the dashboard needs to display, computed without SwiftUI.
///
/// ContentView keeps only layout; all wording and the "sensor absent" rules live
/// here so they are unit-testable on any platform (see tools/swift_harness.cmd).
struct Dashboard {

    enum StatusKind {
        case idle, ok, warn, bad
    }

    let flow: String
    let total: String
    let rpm: String
    let amps: String
    let battery: String

    let ampsMissing: Bool
    let batteryMissing: Bool
    let batteryLow: Bool

    let statusLabel: String
    let statusKind: StatusKind

    let linkRow: String
    let rssiRow: String
    let mtuRow: String
    let uptimeRow: String
    let clientsRow: String

    static func make(frame: Telemetry?,
                     simulate: Bool,
                     state: LinkState,
                     rssi: Int) -> Dashboard {

        let ampsMissing = frame?.a == nil
        let batteryMissing = frame?.v == nil

        return Dashboard(
            flow: frame.map { TelemetryFormatter.flow($0.f) } ?? "--",
            total: frame.map { TelemetryFormatter.total($0.t) } ?? "--",
            rpm: frame.map { TelemetryFormatter.rpm($0.r) } ?? "--",
            amps: TelemetryFormatter.amps(frame?.a),
            battery: TelemetryFormatter.battery(frame?.v),
            ampsMissing: ampsMissing,
            batteryMissing: batteryMissing,
            batteryLow: TelemetryFormatter.isBatteryLow(frame?.v),
            statusLabel: statusLabel(simulate: simulate, state: state),
            statusKind: statusKind(simulate: simulate, state: state),
            linkRow: simulate ? "simulated" : (state.isConnected ? "BLE connected" : "--"),
            rssiRow: simulate ? "-54 dBm" : TelemetryFormatter.rssi(rssi),
            mtuRow: simulate ? "247 (sim)" : "auto by iOS",
            uptimeRow: frame.map { TelemetryFormatter.uptime($0.ms) } ?? "--",
            clientsRow: frame.map { TelemetryFormatter.clients($0.c) } ?? "--"
        )
    }

    static func statusLabel(simulate: Bool, state: LinkState) -> String {
        simulate ? "Simulation" : state.label
    }

    static func statusKind(simulate: Bool, state: LinkState) -> StatusKind {
        if simulate { return .ok }
        switch state {
        case .connected: return .ok
        case .scanning, .connecting: return .warn
        case .failed, .bluetoothOff: return .bad
        case .idle: return .idle
        }
    }
}
