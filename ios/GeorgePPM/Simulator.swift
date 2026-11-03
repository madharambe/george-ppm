import Foundation

/// Synthetic telemetry so the whole UI can be exercised with no ESP32 present.
/// Mirrors the Android Simulator: believable dynamics, a monotonically rising
/// total, and every 20th frame drops the battery to nil to prove the
/// "sensor absent" rendering path.
final class Simulator: ObservableObject {

    @Published private(set) var telemetry: Telemetry?
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private var tick = 0
    private var total = 0.0
    private let startedAt = Date()

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tick = 0
        total = 0.0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.step()
        }
        step()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        telemetry = nil
    }

    func resetTotal() {
        total = 0.0
    }

    private func step() {
        tick += 1
        let flow = 12.5 + 3.0 * sin(Double(tick) / 7.0)
        total += flow / 60.0
        let rpm = Int(1450.0 + 120.0 * sin(Double(tick) / 5.0))
        let amps = 2.1 + 0.35 * sin(Double(tick) / 4.0)
        let battery: Double? = (tick % 20 == 0)
            ? nil
            : 12.6 + 0.4 * sin(Double(tick) / 11.0)

        telemetry = Telemetry(
            f: flow,
            t: total,
            r: rpm,
            a: amps,
            v: battery,
            c: 1,
            ms: Int64(Date().timeIntervalSince(startedAt) * 1000)
        )
    }
}
