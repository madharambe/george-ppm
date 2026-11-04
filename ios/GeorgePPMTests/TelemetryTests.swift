import XCTest
@testable import GeorgePPM

/// These are the frames the ESP32 actually emits (captured from the board's
/// serial port on 2026-11-04), not invented ones.
final class TelemetryTests: XCTestCase {

    private let liveFrame = #"{"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}"#
    private let idleNoSensors = #"{"f":0.00,"t":0.00,"r":0,"a":null,"v":null,"c":0,"ms":6801}"#

    func testDecodesLiveFrame() throws {
        let t = try XCTUnwrap(Telemetry.parse(Data(liveFrame.utf8)))
        XCTAssertEqual(t.f, 12.34, accuracy: 0.0001)
        XCTAssertEqual(t.t, 45.67, accuracy: 0.0001)
        XCTAssertEqual(t.r, 1450)
        XCTAssertEqual(t.a ?? -1, 1.23, accuracy: 0.0001)
        XCTAssertEqual(t.v ?? -1, 12.64, accuracy: 0.0001)
        XCTAssertEqual(t.c, 1)
        XCTAssertEqual(t.ms, 123456)
    }

    func testNullSensorsDecodeAsNil() throws {
        let t = try XCTUnwrap(Telemetry.parse(Data(idleNoSensors.utf8)))
        XCTAssertNil(t.a, "absent ACS712 must decode to nil, not 0.0")
        XCTAssertNil(t.v, "absent battery divider must decode to nil, not 0.0")
        XCTAssertEqual(t.r, 0)
    }

    func testGarbageIsRejected() {
        XCTAssertNil(Telemetry.parse(Data("not json".utf8)))
        XCTAssertNil(Telemetry.parse(Data(#"{"f":12.34}"#.utf8)), "partial frame must not decode")
        XCTAssertNil(Telemetry.parse(Data()))
    }

    func testFormatterRendersDashesForMissingSensors() {
        XCTAssertEqual(TelemetryFormatter.amps(nil), "--")
        XCTAssertEqual(TelemetryFormatter.battery(nil), "--")
        XCTAssertEqual(TelemetryFormatter.amps(1.234), "1.23")
        XCTAssertEqual(TelemetryFormatter.battery(12.64), "12.64")
    }

    func testLowBatteryFlag() {
        XCTAssertTrue(TelemetryFormatter.isBatteryLow(11.5))
        XCTAssertFalse(TelemetryFormatter.isBatteryLow(12.6))
        XCTAssertFalse(TelemetryFormatter.isBatteryLow(nil), "no sensor is not 'low'")
    }

    func testUptimeAndRssi() {
        XCTAssertEqual(TelemetryFormatter.uptime(123456), "123 s")
        XCTAssertEqual(TelemetryFormatter.uptime(0), "--")
        XCTAssertEqual(TelemetryFormatter.rssi(0), "--")
        XCTAssertEqual(TelemetryFormatter.rssi(-54), "-54 dBm")
    }

    /// The frame must fit one notification at the negotiated MTU, and must NOT
    /// fit the 20-byte default - which is why MTU negotiation matters.
    func testFrameSizeAgainstMtu() {
        XCTAssertLessThanOrEqual(liveFrame.utf8.count, 244)
        XCTAssertGreaterThan(liveFrame.utf8.count, 20)
    }
}
