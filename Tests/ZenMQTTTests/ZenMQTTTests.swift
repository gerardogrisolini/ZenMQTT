import XCTest
@testable import ZenMQTT

final class ZenMQTTTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        
        let mqtt = ZenMQTT(host: "test.mosquitto.org", port: 1883, clientID: "Jerry_\(Date())", cleanSession: true, keepAlive: 30)
        mqtt.onMessage = { message in
            print(message.stringRepresentation!)
        }
        
        let topic = "TEST_DEVICE/6304039/PREVENTIVE_MAINTENANCE"
        do {
            try mqtt.start().wait()
            try mqtt.connect().wait()
            try mqtt.subscribe(to: [topic : .atLeastOnce]).wait()
            sleep(1)
            try mqtt.publish(
                "Gerardo Grisolini".data(using: .utf8)!,
                in: topic,
                delivering: .atLeastOnce,
                retain: false
            ).wait()
            sleep(3)
            try mqtt.unSubscribe(from: topic).wait()
            sleep(1)
            try mqtt.disconnect().wait()
            sleep(1)
        } catch {
            XCTFail(error.localizedDescription)
        }
        mqtt.stop()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
