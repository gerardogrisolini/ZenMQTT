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
        
        XCTAssertNoThrow(try mqtt.start().wait())
        XCTAssertNoThrow(try mqtt.connect().wait())
        XCTAssertNoThrow(try mqtt.subscribe(to: ["/topic/test1" : .atLeastOnce]).wait())
        XCTAssertNoThrow(try mqtt.publish(
            "Hello".data(using: .utf8)!,
            in: "/topic/test1" ,
            delivering: .atLeastOnce,
            retain: false
        ).wait())
        sleep(1)
        XCTAssertNoThrow(try mqtt.publish(
            "Gerardo Grisolini".data(using: .utf8)!,
            in: "/topic/test1" ,
            delivering: .atLeastOnce,
            retain: false
        ).wait())
        sleep(1)
        XCTAssertNoThrow(try mqtt.unSubscribe(from: "/topic/test1").wait())
        sleep(1)
        XCTAssertNoThrow(try mqtt.disconnect().wait())
        mqtt.stop()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
