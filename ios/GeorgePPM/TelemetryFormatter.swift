import Foundation

/// Display formatting, deliberately kept free of SwiftUI and CoreBluetooth so it
/// can be unit-tested on a simulator (or in CI) without any hardware.
///
/// The "sensor absent" rule is the important one: a nil reading renders as "--",
/// never as 0.00, because a flat zero is indistinguishable from a genuinely idle
/// load and would mislead an operator.
enum TelemetryFormatter {

    /// Battery below this is flagged as low.
    static let lowBatteryThreshold: Double = 11.8

    static func flow(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func total(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func rpm(_ value: Int) -> String {
        String(value)
    }

    static func amps(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.2f", v)
    }

    static func battery(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.2f", v)
    }

    static func isBatteryLow(_ value: Double?) -> Bool {
        guard let v = value else { return false }
        return v < lowBatteryThreshold
    }

    static func uptime(_ ms: Int64) -> String {
        guard ms > 0 else { return "--" }
        return String(ms / 1000) + " s"
    }

    static func clients(_ n: Int) -> String {
        String(n)
    }

    static func rssi(_ value: Int) -> String {
        value == 0 ? "--" : String(value) + " dBm"
    }
}
