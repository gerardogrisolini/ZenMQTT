//
//  MQTTPublishPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTPublishPacket: MQTTPacket, @unchecked Sendable {

    let messageID: UInt16
    let message: MQTTPubMsg
    let protocolVersion: MQTTProtocolVersion
    
    init(messageID: UInt16, message: MQTTPubMsg, protocolVersion: MQTTProtocolVersion) {
        self.messageID = messageID
        self.message = message
        self.protocolVersion = protocolVersion
        super.init(header: MQTTPacketFixedHeader(packetType: .publish, flags: MQTTPublishPacket.fixedHeaderFlags(for: message)))
    }
    
    class func fixedHeaderFlags(for message: MQTTPubMsg) -> UInt8 {
        var flags = UInt8(0)
        if message.retain {
            flags |= 0x01
        }
        flags |= message.QoS.rawValue << 1
        return flags
    }
    
    override func variableHeader() -> Data {
        var variableHeader = Data(capacity: 1024)
        variableHeader.mqtt_append(message.topic)
        if message.QoS != .atMostOnce {
            variableHeader.mqtt_append(messageID)
        }
        if protocolVersion == .v500 {
            let propertiesData = encodeProperties()
            variableHeader.mqtt_appendVariableInteger(propertiesData.count)
            variableHeader.append(propertiesData)
        }
        return variableHeader
    }
    
    override func payload() -> Data {
        return message.payload
    }
    
    init(header: MQTTPacketFixedHeader, networkData: Data, protocolVersion: MQTTProtocolVersion) {
        self.protocolVersion = protocolVersion
        let topicLength = 256 * Int(networkData[0]) + Int(networkData[1])
        let topicData = networkData.subdata(in: 2..<topicLength+2)
        let topic = String(data: topicData, encoding: .utf8)!
        
        let qos = MQTTQoS(rawValue: (header.flags & 0x06) >> 1) ?? .atMostOnce
        var payloadStart = 2 + topicLength
        
        if qos != .atMostOnce {
            let midData = networkData.subdata(in: payloadStart..<payloadStart + 2)
            messageID = 256 * UInt16(midData[0]) + UInt16(midData[1])
            payloadStart += 2
        } else {
            messageID = 0
        }

        if protocolVersion == .v500,
           let (propertiesLength, consumed) = mqtt_decodeVariableInteger(from: networkData, at: payloadStart) {
            let propertiesStart = payloadStart + consumed
            let propertiesEnd = min(propertiesStart + propertiesLength, networkData.count)
            let publishProperties = Self.decodeProperties(from: networkData.subdata(in: propertiesStart..<propertiesEnd))
            payloadStart = propertiesEnd

            let payload = payloadStart < networkData.endIndex
                ? networkData.subdata(in: payloadStart..<networkData.endIndex)
                : Data()

            let retain = (header.flags & 0x01) == 0x01
            message = MQTTPubMsg(topic: topic, payload: payload, retain: retain, QoS: qos, properties: publishProperties)
            super.init(header: header)
            return
        }

        let payload = payloadStart < networkData.endIndex
            ? networkData.subdata(in: payloadStart..<networkData.endIndex)
            : Data()
        
        let retain = (header.flags & 0x01) == 0x01
        message = MQTTPubMsg(topic: topic, payload: payload, retain: retain, QoS: qos, properties: nil)
        
        super.init(header: header)
    }

    private func encodeProperties() -> Data {
        var data = Data()
        guard let properties = message.properties else { return data }

        if let payloadFormatIndicator = properties.payloadFormatIndicator {
            data.mqtt_append(UInt8(0x01))
            data.mqtt_append(payloadFormatIndicator)
        }
        if let messageExpiryInterval = properties.messageExpiryInterval {
            data.mqtt_append(UInt8(0x02))
            data.mqtt_append(messageExpiryInterval)
        }
        if let contentType = properties.contentType {
            data.mqtt_append(UInt8(0x03))
            data.mqtt_append(contentType)
        }
        if let responseTopic = properties.responseTopic {
            data.mqtt_append(UInt8(0x08))
            data.mqtt_append(responseTopic)
        }
        if let correlationData = properties.correlationData {
            data.mqtt_append(UInt8(0x09))
            data.mqtt_append(correlationData)
        }
        if let topicAlias = properties.topicAlias {
            data.mqtt_append(UInt8(0x23))
            data.mqtt_append(topicAlias)
        }

        return data
    }

    private static func decodeProperties(from data: Data) -> MQTTPublishProperties {
        var properties = MQTTPublishProperties()
        var index = 0

        while index < data.count {
            let id = data[index]
            index += 1

            switch id {
            case 0x01: // Payload Format Indicator
                guard index < data.count else { return properties }
                properties.payloadFormatIndicator = data[index]
                index += 1
            case 0x02: // Message Expiry Interval
                guard let value = mqtt_readUInt32(from: data, at: index) else { return properties }
                properties.messageExpiryInterval = value
                index += 4
            case 0x03: // Content Type
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return properties }
                properties.contentType = value
                index += consumed
            case 0x08: // Response Topic
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return properties }
                properties.responseTopic = value
                index += consumed
            case 0x09: // Correlation Data
                guard let (value, consumed) = mqtt_readBinaryData(from: data, at: index) else { return properties }
                properties.correlationData = value
                index += consumed
            case 0x23: // Topic Alias
                guard let value = mqtt_readUInt16(from: data, at: index) else { return properties }
                properties.topicAlias = value
                index += 2
            default:
                return properties
            }
        }

        return properties
    }
}
