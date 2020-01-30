import XCTest
import NIO
@testable import ZenMQTT

final class ZenMQTTTests: XCTestCase {
    
    var eventLoopGroup: MultiThreadedEventLoopGroup!
    
    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    override func tearDown() {
        try! eventLoopGroup.syncShutdownGracefully()
    }
    
    func testExample() {
        let mqtt = ZenMQTT(host: "test.mosquitto.org", port: 1883, clientID: "Jerry_\(Date())", cleanSession: true, eventLoopGroup: eventLoopGroup)
        mqtt.onMessage = { message in
            print(message.stringRepresentation!)
        }
        
        do {
            try mqtt.start().wait()
            try mqtt.connect().wait()
            
            let topic = "TEST_DEVICE/6304039/PREVENTIVE_MAINTENANCE"
            try mqtt.subscribe(to: [topic : .atLeastOnce]).wait()
            try mqtt.publish(
                "Gerardo Grisolini".data(using: .utf8)!,
                in: topic,
                delivering: .atLeastOnce,
                retain: false
            ).wait()
            sleep(3)
            try mqtt.unsubscribe(from: topic).wait()
            try mqtt.disconnect().wait()
            try mqtt.stop().wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
