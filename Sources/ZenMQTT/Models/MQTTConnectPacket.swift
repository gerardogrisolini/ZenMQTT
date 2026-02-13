//
//  MQTTConnectPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTConnectPacket: MQTTPacket, @unchecked Sendable {
    
    let protocolName: String
    let protocolVersion: MQTTProtocolVersion
    let cleanSession: Bool
    let keepAlive: UInt16
    let clientID: String
    let connectProperties: MQTTConnectProperties?
    
    var username: String? = nil
    var password: String? = nil
    var lastWillMessage: MQTTPubMsg? = nil
    
    init(
        clientID: String,
        cleanSession: Bool,
        keepAlive: UInt16,
        protocolVersion: MQTTProtocolVersion,
        connectProperties: MQTTConnectProperties?
    ) {
        self.protocolName = "MQTT"
        self.protocolVersion = protocolVersion
        self.cleanSession = cleanSession
        self.keepAlive = keepAlive
        self.clientID = clientID
        self.connectProperties = connectProperties
        super.init(header: MQTTPacketFixedHeader(packetType: .connect, flags: 0))
    }
    
    func encodedConnectFlags() -> UInt8 {
        var flags = UInt8(0)
        if cleanSession {
            flags |= 0x02
        }
        
        if let message = lastWillMessage {
            flags |= 0x04
            
            if message.retain {
                flags |= 0x20
            }
            let qos = message.QoS.rawValue
            flags |= qos << 3
        }
        
        if username != nil {
            flags |= 0x80
        }
        
        if password != nil {
            flags |= 0x40
        }
        
        return flags
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data(capacity: 1024)
        variableHeader.mqtt_append(protocolName)
        variableHeader.mqtt_append(protocolVersion.rawValue)
        variableHeader.mqtt_append(encodedConnectFlags())
        variableHeader.mqtt_append(keepAlive)
        if protocolVersion == .v500 {
            var properties = Data()
            if let sessionExpiryInterval = connectProperties?.sessionExpiryInterval {
                properties.mqtt_append(UInt8(0x11))
                properties.mqtt_append(sessionExpiryInterval)
            }
            if let receiveMaximum = connectProperties?.receiveMaximum {
                properties.mqtt_append(UInt8(0x21))
                properties.mqtt_append(receiveMaximum)
            }
            if let maximumPacketSize = connectProperties?.maximumPacketSize {
                properties.mqtt_append(UInt8(0x27))
                properties.mqtt_append(maximumPacketSize)
            }
            if let topicAliasMaximum = connectProperties?.topicAliasMaximum {
                properties.mqtt_append(UInt8(0x22))
                properties.mqtt_append(topicAliasMaximum)
            }
            variableHeader.mqtt_appendVariableInteger(properties.count)
            variableHeader.append(properties)
        }
        return variableHeader
    }
    
    override func payload() -> Data {
        var payload = Data(capacity: 1024)
        payload.mqtt_append(clientID)
        
        if let message = lastWillMessage {
            if protocolVersion == .v500 {
                payload.mqtt_appendVariableInteger(0) // Will properties
            }
            payload.mqtt_append(message.topic)
            payload.mqtt_append(message.payload)
        }
        if let username = username {
            payload.mqtt_append(username)
        }
        if let password = password {
            payload.mqtt_append(password)
        }
        return payload
    }
}
