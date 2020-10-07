//
//  MQTTPubAck.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

class MQTTPubAck: MQTTPacket {
    
    let messageID: UInt16
    
    init(messageID: UInt16) {
        self.messageID = messageID
        super.init(header: MQTTPacketFixedHeader(packetType: MQTTPacketType.pubAck, flags: 0))
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data()
        variableHeader.mqtt_append(messageID)
        return variableHeader
    }
    
    init(header: MQTTPacketFixedHeader, networkData: Data) {
        messageID = (UInt16(networkData[0]) * UInt16(256)) + UInt16(networkData[1])
        super.init(header: header)
    }
}
