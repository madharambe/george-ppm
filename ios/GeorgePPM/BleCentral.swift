import Foundation
import CoreBluetooth

/// CoreBluetooth central for the George PPM ESP32.
///
/// Differences from the Android client that are easy to get wrong:
///  - iOS does NOT let an app request an ATT MTU. CoreBluetooth negotiates it
///    automatically (typically 185 bytes of payload), comfortably more than our
///    ~67-byte frame, so no MTU call is needed here.
///  - The CCCD is written by CoreBluetooth when setNotifyValue(_:for:) is called;
///    there is no descriptor write to do by hand.
///  - Scanning must wait for centralManager.state == .poweredOn; scanning earlier
///    is silently ignored.
///  - CoreBluetooth filters scans on the ADVERTISEMENT packet, which is why the
///    firmware puts the 128-bit service UUID there and the name in the scan
///    response.
final class BleCentral: NSObject, ObservableObject {

    enum LinkState: Equatable {
        case idle
        case bluetoothOff
        case scanning
        case connecting(String)
        case connected(String)
        case failed(String)
    }

    static let serviceUUID = CBUUID(string: "4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6")
    static let telemetryUUID = CBUUID(string: "4a5b6c7d-0002-4d8e-9f00-a1b2c3d4e5f6")
    static let commandUUID = CBUUID(string: "4a5b6c7d-0003-4d8e-9f00-a1b2c3d4e5f6")

    @Published private(set) var state: LinkState = .idle
    @Published private(set) var telemetry: Telemetry?
    @Published private(set) var rssi: Int = 0
    @Published private(set) var log: [String] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var rssiTimer: Timer?

    override init() {
        super.init()
        // queue: .main keeps every delegate callback on the main thread, so the
        // @Published mutations below are safe without extra hopping.
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    // MARK: - Public API

    func start() {
        guard central.state == .poweredOn else {
            append("Bluetooth not ready (" + stateText(central.state) + ")")
            state = .bluetoothOff
            return
        }
        append("Scanning for GeorgePPM...")
        state = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    func stop() {
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        central.stopScan()
        tearDown()
        state = .idle
    }

    func resetTotal() {
        write("RESET")
    }

    func write(_ command: String) {
        guard let p = peripheral, let ch = commandChar else {
            append("Not connected - cannot send " + command)
            return
        }
        p.writeValue(Data(command.utf8), for: ch, type: .withoutResponse)
        append("Sent " + command)
    }

    // MARK: - Internals

    private func tearDown() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        peripheral = nil
        commandChar = nil
        rssi = 0
    }

    private func append(_ line: String) {
        let stamp = Self.formatter.string(from: Date())
        log.append(stamp + "  " + line)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func stateText(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOn: return "on"
        case .poweredOff: return "off"
        case .unauthorized: return "unauthorized - check Settings > Privacy > Bluetooth"
        case .unsupported: return "unsupported on this device"
        case .resetting: return "resetting"
        case .unknown: return "unknown"
        @unknown default: return "unexpected"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BleCentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        append("Central state: " + stateText(central.state))
        if central.state != .poweredOn {
            state = .bluetoothOff
        } else if case .bluetoothOff = state {
            state = .idle
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "GeorgePPM"
        append("Found " + name + " (rssi " + String(RSSI.intValue) + ")")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting(name)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "GeorgePPM"
        append("Connected to " + name)
        state = .connected(name)
        peripheral.discoverServices([Self.serviceUUID])

        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak peripheral] _ in
            peripheral?.readRSSI()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        append("Connect failed: " + (error?.localizedDescription ?? "unknown"))
        state = .failed(error?.localizedDescription ?? "connect failed")
        tearDown()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let suffix = error.map { ": " + $0.localizedDescription } ?? ""
        append("Disconnected" + suffix)
        state = .idle
        tearDown()
    }
}

// MARK: - CBPeripheralDelegate

extension BleCentral: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            append("Service discovery failed: " + error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            append("GeorgePPM service not found")
            return
        }
        peripheral.discoverCharacteristics(
            [Self.telemetryUUID, Self.commandUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            append("Characteristic discovery failed: " + error.localizedDescription)
            return
        }
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.telemetryUUID {
                // CoreBluetooth writes the CCCD descriptor for us.
                peripheral.setNotifyValue(true, for: ch)
                append("Subscribing to telemetry...")
            } else if ch.uuid == Self.commandUUID {
                commandChar = ch
            }
        }
        peripheral.readRSSI()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            append("Subscribe failed: " + error.localizedDescription)
        } else if characteristic.isNotifying {
            append("Subscribed - receiving telemetry")
        } else {
            append("Notifications disabled")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.telemetryUUID,
              let data = characteristic.value else { return }
        if let frame = Telemetry.parse(data) {
            telemetry = frame
        } else {
            append("Bad frame: " + (String(data: data, encoding: .utf8) ?? "<binary>"))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        rssi = RSSI.intValue
    }
}
