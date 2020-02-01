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
            
            let topic1 = "test/topic1"
            let topic2 = "test/topic2"
            try mqtt.subscribe(to: [topic1 : .atLeastOnce, topic2 : .atLeastOnce]).wait()
            
            sleep(3)
            let message1 = MQTTPubMsg(topic: topic1, payload: "Hello world!".data(using: .utf8)!, retain: false, QoS: .atLeastOnce)
            try mqtt.publish(message: message1).wait()

            sleep(3)
            let message2 = MQTTPubMsg(topic: topic2, payload: "Gerardo Grisolini".data(using: .utf8)!, retain: false, QoS: .atLeastOnce)
            try mqtt.publish(message: message2).wait()
            
            sleep(3)
            try mqtt.unsubscribe(from: [topic1, topic2]).wait()
            try mqtt.disconnect().wait()
        } catch {
            XCTFail("\(error)")
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
