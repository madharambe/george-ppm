import Foundation
import Combine

/// Synthetic telemetry, so the whole UI can be exercised with no ESP32 present.
///
/// The generator itself lives in SyntheticTelemetry.swift (Foundation-only, so
/// it compiles and is tested on Windows too). This file is only the Combine /
/// SwiftUI plumbing around it.
final class Simulator: ObservableObject {

    @Published private(set) var telemetry: Telemetry?
    @Published private(set) var isRunning = false

    private var generator = SyntheticTelemetry()
    private var timer: Timer?
    private let startedAt = Date()

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generator = SyntheticTelemetry()
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
        generator.resetTotal()
    }

    private func step() {
        let uptime = Int64(Date().timeIntervalSince(startedAt) * 1000)
        telemetry = generator.next(uptimeMs: uptime)
    }
}
