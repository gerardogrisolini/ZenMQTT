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
        let mqtt = ZenMQTT(host: "test.mosquitto.org", port: 1883, clientID: "test_\(Date())", cleanSession: true, eventLoopGroup: eventLoopGroup)
        
        mqtt.onMessageReceived = { message in
            print(message.stringRepresentation!)
        }
        
        mqtt.onHandlerRemoved = {
            print("Handler removed")
        }

        mqtt.onErrorCaught = { error in
            print(error.localizedDescription)
        }
        
        do {
            try mqtt.connect().wait()
            
            let topic = "VIET_DEVICE/6304039/PREVENTIVE_MAINTENANCE"
            try mqtt.subscribe(to: [topic : .atLeastOnce]).wait()
            sleep(3)
            try mqtt.publish(
                "Hello world!".data(using: .utf8)!,
                in: topic,
                delivering: .atLeastOnce,
                retain: false
            ).wait()
            sleep(20)
            try mqtt.unsubscribe(from: topic).wait()
            try mqtt.disconnect().wait()
        } catch {
            XCTFail("\(error)")
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
