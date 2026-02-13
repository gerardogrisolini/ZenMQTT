//
//  MQTTConnAckPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//


import Foundation

final class MQTTConnAckPacket: MQTTPacket, @unchecked Sendable {
    
    let sessionPresent: Bool
    let response: MQTTConnAckResponse
    let protocolVersion: MQTTProtocolVersion
    let properties: MQTTConnAckProperties?
    
    init(header: MQTTPacketFixedHeader, networkData: Data, protocolVersion: MQTTProtocolVersion) {
        self.protocolVersion = protocolVersion
        sessionPresent = (networkData[0] & 0x01) == 0x01
        response = MQTTConnAckResponse(rawValue: networkData[1]) ?? .serverUnavailable
        if protocolVersion == .v500 {
            properties = MQTTConnAckPacket.decodeProperties(from: networkData)
        } else {
            properties = nil
        }
        
        super.init(header: header)
    }

    private static func decodeProperties(from networkData: Data) -> MQTTConnAckProperties {
        guard let (propertiesLength, consumed) = mqtt_decodeVariableInteger(from: networkData, at: 2) else {
            return MQTTConnAckProperties()
        }

        var properties = MQTTConnAckProperties()
        var index = 2 + consumed
        let end = min(index + propertiesLength, networkData.count)

        while index < end {
            let id = networkData[index]
            index += 1

            switch id {
            case 0x11: // Session Expiry Interval
                if let value = mqtt_readUInt32(from: networkData, at: index) {
                    properties.sessionExpiryInterval = value
                    index += 4
                } else {
                    return properties
                }
            case 0x21: // Receive Maximum
                if let value = mqtt_readUInt16(from: networkData, at: index) {
                    properties.receiveMaximum = value
                    index += 2
                } else {
                    return properties
                }
            case 0x27: // Maximum Packet Size
                if let value = mqtt_readUInt32(from: networkData, at: index) {
                    properties.maximumPacketSize = value
                    index += 4
                } else {
                    return properties
                }
            case 0x22: // Topic Alias Maximum
                if let value = mqtt_readUInt16(from: networkData, at: index) {
                    properties.topicAliasMaximum = value
                    index += 2
                } else {
                    return properties
                }
            case 0x13: // Server Keep Alive
                if let value = mqtt_readUInt16(from: networkData, at: index) {
                    properties.serverKeepAlive = value
                    index += 2
                } else {
                    return properties
                }
            default:
                // Unknown property: stop to avoid malformed cursor advancement.
                return properties
            }
        }

        return properties
    }
}
