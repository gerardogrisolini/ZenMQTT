//
//  MQTTSubPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTSubPacket: MQTTPacket, @unchecked Sendable {
    
    let topics: [String: MQTTQoS]
    let messageID: UInt16
    let protocolVersion: MQTTProtocolVersion
    
    init(topics: [String: MQTTQoS], messageID: UInt16, protocolVersion: MQTTProtocolVersion) {
        self.topics = topics
        self.messageID = messageID
        self.protocolVersion = protocolVersion
        super.init(header: MQTTPacketFixedHeader(packetType: .subscribe, flags: 0x02))
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data()
        variableHeader.mqtt_append(messageID)
        if protocolVersion == .v500 {
            variableHeader.mqtt_appendVariableInteger(0) // SUBSCRIBE properties
        }
        return variableHeader
    }
    
    override func payload() -> Data {
        var payload = Data(capacity: 1024)
        for (key, value) in topics {
            payload.mqtt_append(key)
            let qos = value.rawValue & 0x03
            payload.mqtt_append(qos)
        }
        return payload
    }
}
