import XCTest
import NIO
@testable import ZenMQTT

final class ZenMQTTTests: XCTestCase {
    
    var eventLoopGroup: MultiThreadedEventLoopGroup!
    
    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    override func tearDown() {
        try! eventLoopGroup.syncShutdownGracefully()
    }
    
    func testMQTTv311() async throws {
        try await runScenario(version: .v311)
    }

    func testMQTTv500() async throws {
        try await runScenario(version: .v500)
    }

    func testDecodePubAckFailureReasonCode() {
        let header = MQTTPacketFixedHeader(packetType: .pubAck, flags: 0)
        let data = Data([0x00, 0x0A, 0x87, 0x00]) // packetId=10, reasonCode=Not Authorized, empty props
        let packet = MQTTPubAck(header: header, networkData: data, protocolVersion: .v500)

        XCTAssertTrue(packet.reasonCode.isFailure)
        XCTAssertEqual(packet.messageID, 10)
    }

    func testDecodeAuthPacket() {
        let header = MQTTPacketFixedHeader(packetType: .auth, flags: 0)
        var data = Data()
        data.append(0x18) // Continue authentication

        var props = Data()
        props.append(0x15) // Authentication Method
        props.mqtt_append("SCRAM-SHA-256")
        props.append(0x16) // Authentication Data
        props.mqtt_append("step-1".data(using: .utf8)!)
        props.append(0x1F) // Reason String
        props.mqtt_append("challenge")
        data.mqtt_appendVariableInteger(props.count)
        data.append(props)

        let packet = MQTTAuthPacket(header: header, networkData: data)
        XCTAssertEqual(packet.reasonCode, .continue)
        XCTAssertEqual(packet.properties?.authenticationMethod, "SCRAM-SHA-256")
        XCTAssertEqual(String(data: packet.properties?.authenticationData ?? Data(), encoding: .utf8), "step-1")
        XCTAssertEqual(packet.properties?.reasonString, "challenge")
    }

    func testDecodePubRecRelCompPackets() {
        let recHeader = MQTTPacketFixedHeader(packetType: .pubRec, flags: 0)
        let relHeader = MQTTPacketFixedHeader(packetType: .pubRel, flags: 0x02)
        let compHeader = MQTTPacketFixedHeader(packetType: .pubComp, flags: 0)

        let rec = MQTTPubRecPacket(header: recHeader, networkData: Data([0x00, 0x0A, 0x00, 0x00]), protocolVersion: .v500)
        let rel = MQTTPubRelPacket(header: relHeader, networkData: Data([0x00, 0x0A, 0x00, 0x00]), protocolVersion: .v500)
        let comp = MQTTPubCompPacket(header: compHeader, networkData: Data([0x00, 0x0A, 0x00, 0x00]), protocolVersion: .v500)

        XCTAssertEqual(rec.messageID, 10)
        XCTAssertEqual(rel.messageID, 10)
        XCTAssertEqual(comp.messageID, 10)
        XCTAssertFalse(rec.reasonCode.isFailure)
        XCTAssertFalse(rel.reasonCode.isFailure)
        XCTAssertFalse(comp.reasonCode.isFailure)
    }

    private func runScenario(version: MQTTProtocolVersion) async throws {
        let env = ProcessInfo.processInfo.environment
        let host = env["MQTT_TEST_HOST"] ?? "test.mosquitto.org"
        let port = Int(env["MQTT_TEST_PORT"] ?? "8884") ?? 8884
        let certPath = env["MQTT_CLIENT_CERT"] ?? "/Users/gerardo/Projects/ZenMQTT/certs/test-mosquitto-client.crt"
        let keyPath = env["MQTT_CLIENT_KEY"] ?? "/Users/gerardo/Projects/ZenMQTT/certs/test-mosquitto-client.key"
        let clientID = "test_\(UUID().uuidString)"

        guard FileManager.default.fileExists(atPath: certPath) else {
            throw XCTSkip("mTLS certificate not found at \(certPath)")
        }
        guard FileManager.default.fileExists(atPath: keyPath) else {
            throw XCTSkip("mTLS private key not found at \(keyPath)")
        }

        let mqtt = ZenMQTT(host: host, port: port, clientID: clientID, reconnect: true, protocolVersion: version, eventLoopGroup: eventLoopGroup)
        XCTAssertNoThrow(try mqtt.addTLS(cert: certPath, key: keyPath))
        
        mqtt.onMessageReceived = { message in
            print(message.stringRepresentation!)
        }
        
        mqtt.onHandlerRemoved = {
            print("Handler removed")
        }

        mqtt.onErrorCaught = { error in
            print(error.localizedDescription)
        }
        
        let topic = "zenmqtt/test/\(clientID)"

        let connectProperties: MQTTConnectProperties? = version == .v500
            ? MQTTConnectProperties(
                sessionExpiryInterval: 60,
                receiveMaximum: 20,
                maximumPacketSize: 1_048_576,
                topicAliasMaximum: 10
            )
            : nil

        try await mqtt.connect(cleanSession: true, keepAlive: 30, protocolVersion: version, connectProperties: connectProperties)
        try await mqtt.subscribe(to: [topic : .atLeastOnce])

        for i in 0...10 {
            let publishProperties: MQTTPublishProperties? = version == .v500
                ? MQTTPublishProperties(
                    payloadFormatIndicator: 1,
                    messageExpiryInterval: 60,
                    contentType: "text/plain",
                    responseTopic: "zenmqtt/resp/\(clientID)",
                    correlationData: "corr-\(i)".data(using: .utf8),
                    topicAlias: 1
                )
                : nil
            let message = MQTTPubMsg(
                topic: topic,
                payload: "Hello world \(i)!".data(using: .utf8)!,
                retain: false,
                QoS: .atLeastOnce,
                properties: publishProperties
            )
            try await mqtt.publish(message: message)
        }

        let qos2Message = MQTTPubMsg(
            topic: topic,
            payload: "Hello qos2".data(using: .utf8)!,
            retain: false,
            QoS: .exactlyOnce,
            properties: version == .v500 ? MQTTPublishProperties(contentType: "text/plain") : nil
        )
        try await mqtt.publish(message: qos2Message)

        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        try await mqtt.unsubscribe(from: [topic])
        try await mqtt.disconnect()
    }
}
