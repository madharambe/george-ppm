// TEST ONLY shim - compiled into a fake "CoreBluetooth" module so BleCentral.swift
// can be type-checked on Windows. Signatures mirror Apple's documentation; the
// real framework is verified separately by tools/ios_preflight.py (delegate
// selectors) so a shim/real divergence cannot silently pass.
import Foundation

public struct CBUUID: Equatable, Hashable {
    public let uuidString: String
    public init(string: String) { self.uuidString = string }
    public init(string theString: String, isStatic: Bool) { self.uuidString = theString }
}

public enum CBManagerState: Int {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public enum CBCharacteristicWriteType: Int {
    case withResponse, withoutResponse
}

public let CBCentralManagerOptionShowPowerAlertKey = "kCBPeripheralManagerOptionShowPowerAlertKey"
public let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"

open class CBService {
    open var uuid: CBUUID = CBUUID(string: "")
    open var characteristics: [CBCharacteristic]?
    public init() {}
}

open class CBCharacteristic {
    open var uuid: CBUUID = CBUUID(string: "")
    open var value: Data?
    open var isNotifying: Bool = false
    public init() {}
}

open class CBPeripheral {
    open var delegate: CBPeripheralDelegate?
    open var name: String?
    open var services: [CBService]?
    public init() {}

    open func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    open func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    open func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    open func readRSSI() {}
    open func writeValue(_ data: Data, for characteristic: CBCharacteristic,
                         type: CBCharacteristicWriteType) {}
}

public protocol CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)
}

open class CBCentralManager {
    public var state: CBManagerState = .unknown
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?,
                options: [String: Any]? = nil) {}
    open func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
    open func stopScan() {}
    open func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {}
    open func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
}

public protocol CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}
