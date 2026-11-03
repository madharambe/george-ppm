import Foundation

/// One telemetry frame from the ESP32.
///
/// Wire format (ASCII JSON, published on the notify characteristic):
///   {"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}
///
/// The short property names match the JSON keys exactly, so Decodable maps them
/// without CodingKeys. "a" and "v" are optional because the firmware sends null
/// when a sensor is not detected - a fake 0.00 A would be indistinguishable from
/// a genuinely idle load, which is the wrong thing to show an operator.
struct Telemetry: Decodable, Equatable {
    let f: Double      // flow, L/min
    let t: Double      // total volume, L
    let r: Int         // RPM
    let a: Double?     // current, A  (nil = ACS712 not detected)
    let v: Double?     // battery, V  (nil = divider not fitted)
    let c: Int         // connected BLE clients
    let ms: Int64      // ESP32 uptime, ms

    static func parse(_ data: Data) -> Telemetry? {
        try? JSONDecoder().decode(Telemetry.self, from: data)
    }
}
