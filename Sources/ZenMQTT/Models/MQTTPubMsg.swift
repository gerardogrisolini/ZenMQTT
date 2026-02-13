//
//  MQTTPubMsg.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

public struct MQTTPubMsg {
    
    public let topic: String
    public let payload: Data
    public let retain: Bool
    public let QoS: MQTTQoS
    public let properties: MQTTPublishProperties?
    
    public init(topic: String, payload: Data, retain: Bool, QoS: MQTTQoS, properties: MQTTPublishProperties? = nil) {
        self.topic = topic
        self.payload = payload
        self.retain = retain
        self.QoS = QoS
        self.properties = properties
    }
}
