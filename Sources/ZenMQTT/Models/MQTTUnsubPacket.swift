//
//  MQTTUnsubPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTUnsubPacket: MQTTPacket, @unchecked Sendable {
    
    let topics: [String]
    let messageID: UInt16
    let protocolVersion: MQTTProtocolVersion
    
    init(topics: [String], messageID: UInt16, protocolVersion: MQTTProtocolVersion) {
        self.topics = topics
        self.messageID = messageID
        self.protocolVersion = protocolVersion
        super.init(header: MQTTPacketFixedHeader(packetType: .unSubscribe, flags: 0x02))
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data()
        variableHeader.mqtt_append(messageID)
        if protocolVersion == .v500 {
            variableHeader.mqtt_appendVariableInteger(0) // UNSUBSCRIBE properties
        }
        return variableHeader
    }
    
    override func payload() -> Data {
        var payload = Data(capacity: 1024)
        for topic in topics {
            payload.mqtt_append(topic)
        }
        return payload
    }
}
