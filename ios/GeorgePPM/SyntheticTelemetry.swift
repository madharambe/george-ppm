import Foundation

/// Deterministic synthetic telemetry for hardware-free testing.
///
/// Extracted from Simulator.swift so the generator itself is Foundation-only and
/// therefore compiles and is testable on any platform. Simulator.swift keeps
/// only the Combine plumbing around it.
///
/// Behaviour worth pinning down (and asserted in tests/swift/main.swift):
///   - the total only ever increases
///   - flow/RPM/current oscillate within believable bounds
///   - every 20th frame drops the battery to nil, to exercise the
///     "sensor absent" path in the UI
struct SyntheticTelemetry {

    private(set) var tick = 0
    private(set) var total = 0.0

    mutating func resetTotal() {
        total = 0.0
    }

    mutating func next(uptimeMs: Int64) -> Telemetry {
        tick += 1
        let flow = 12.5 + 3.0 * sin(Double(tick) / 7.0)      // L/min
        total += flow / 60.0                                  // litres per second
        let rpm = Int(1450.0 + 120.0 * sin(Double(tick) / 5.0))
        let amps = 2.1 + 0.35 * sin(Double(tick) / 4.0)
        let battery: Double? = (tick % 20 == 0)
            ? nil
            : 12.6 + 0.4 * sin(Double(tick) / 11.0)

        return Telemetry(
            f: flow,
            t: total,
            r: rpm,
            a: amps,
            v: battery,
            c: 1,
            ms: uptimeMs
        )
    }
}
