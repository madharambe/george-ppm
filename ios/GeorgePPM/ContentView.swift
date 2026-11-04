import SwiftUI

private enum Theme {
    static let bg = Color(red: 0.055, green: 0.078, blue: 0.094)
    static let surface = Color(red: 0.086, green: 0.118, blue: 0.141)
    static let surfaceHigh = Color(red: 0.118, green: 0.161, blue: 0.200)
    static let accent = Color(red: 0.133, green: 0.827, blue: 0.933)
    static let good = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let warn = Color(red: 0.984, green: 0.749, blue: 0.141)
    static let bad = Color(red: 0.973, green: 0.443, blue: 0.443)
    static let text = Color(red: 0.910, green: 0.937, blue: 0.961)
    static let muted = Color(red: 0.561, green: 0.639, blue: 0.702)
    static let divider = Color(red: 0.141, green: 0.196, blue: 0.251)
}

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}

private struct MetricTile: View {
    let label: String
    let value: String
    let unit: String
    var muted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(muted ? Theme.muted : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var ble = BleCentral()
    @StateObject private var sim = Simulator()
    @State private var simulate = false

    private var frame: Telemetry? {
        simulate ? sim.telemetry : ble.telemetry
    }

    private var statusText: String {
        if simulate { return "Simulation" }
        switch ble.state {
        case .idle: return "Idle"
        case .bluetoothOff: return "Bluetooth off"
        case .scanning: return "Scanning..."
        case .connecting(let name): return "Connecting " + name
        case .connected(let name): return "Connected - " + name
        case .failed(let why): return "Failed: " + why
        }
    }

    private var statusColor: Color {
        if simulate { return Theme.accent }
        switch ble.state {
        case .connected: return Theme.good
        case .scanning, .connecting: return Theme.warn
        case .failed, .bluetoothOff: return Theme.bad
        case .idle: return Theme.surfaceHigh
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    heroCard
                    metricGrid
                    connectionCard
                    logCard
                    simulationCard
                    actionButtons
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("George PPM")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Theme.text)
            Text("Water flow - RPM - current monitor")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.22))
                .clipShape(Capsule())
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private var heroCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text("DEBIT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(frame.map { TelemetryFormatter.flow($0.f) } ?? "--")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.text)
                    Text("L/min")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                }
            }
        }
    }

    private var metricGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Card { MetricTile(label: "Total", value: frame.map { TelemetryFormatter.total($0.t) } ?? "--", unit: "L") }
                Card { MetricTile(label: "RPM", value: frame.map { TelemetryFormatter.rpm($0.r) } ?? "--", unit: "rev/min") }
            }
            HStack(spacing: 12) {
                Card {
                    MetricTile(
                        label: "Arus",
                        value: TelemetryFormatter.amps(frame?.a),
                        unit: "A",
                        muted: frame?.a == nil
                    )
                }
                Card {
                    MetricTile(
                        label: "Baterai",
                        value: TelemetryFormatter.battery(frame?.v),
                        unit: "V",
                        muted: frame?.v == nil
                    )
                }
            }
        }
    }

    private var connectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("CONNECTION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(Theme.muted)
                VStack(alignment: .leading, spacing: 3) {
                    metaRow("link", simulate ? "simulated" : (ble.isConnected ? "BLE connected" : "--"))
                    metaRow("rssi", simulate ? "-54 dBm" : TelemetryFormatter.rssi(ble.rssi))
                    metaRow("mtu", simulate ? "247 (sim)" : "auto by iOS")
                    metaRow("uptime", frame.map { TelemetryFormatter.uptime($0.ms) } ?? "--")
                    metaRow("clients", frame.map { TelemetryFormatter.clients($0.c) } ?? "--")
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.text)
            }
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .foregroundColor(Theme.muted)
                .frame(width: 70, alignment: .leading)
            Text(value)
            Spacer()
        }
    }

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("EVENT LOG")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(Theme.muted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(ble.log.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private var simulationCard: some View {
        Card {
            Toggle(isOn: $simulate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simulation mode")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.text)
                    Text("Synthetic frames, so the UI can be checked without the board.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
            .onChange(of: simulate) { on in
                if on {
                    ble.stop()
                    sim.start()
                } else {
                    sim.stop()
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                if ble.isConnected { ble.stop() } else { ble.start() }
            } label: {
                Text(ble.isConnected ? "Disconnect" : "Scan & Connect")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundColor(Color(red: 0.024, green: 0.133, blue: 0.165))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(simulate)

            Button {
                if simulate { sim.resetTotal() } else { ble.resetTotal() }
            } label: {
                Text("Reset Total")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.surfaceHigh)
                    .foregroundColor(Theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
