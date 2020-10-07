//
//  MQTTSubPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

class MQTTSubPacket: MQTTPacket {
    
    let topics: [String: MQTTQoS]
    let messageID: UInt16
    
    init(topics: [String: MQTTQoS], messageID: UInt16) {
        self.topics = topics
        self.messageID = messageID
        super.init(header: MQTTPacketFixedHeader(packetType: .subscribe, flags: 0x02))
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data()
        variableHeader.mqtt_append(messageID)
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
