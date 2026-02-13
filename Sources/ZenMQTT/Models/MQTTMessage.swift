//
//  MQTTMessage.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

public struct MQTTMessage {
    public let topic: String
    public let payload: Data
    public let id: UInt16
    public let retain: Bool
    public let properties: MQTTPublishProperties?
    
    internal init(publishPacket: MQTTPublishPacket) {
        self.topic = publishPacket.message.topic
        self.payload = publishPacket.message.payload
        self.id = publishPacket.messageID
        self.retain = publishPacket.message.retain
        self.properties = publishPacket.message.properties
    }
    
    public var stringRepresentation: String? {
        return String(data: self.payload, encoding: .utf8)
    }
}
