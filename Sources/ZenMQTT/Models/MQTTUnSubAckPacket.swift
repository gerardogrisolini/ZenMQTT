//
//  MQTTUnSubAckPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTUnSubAckPacket: MQTTPacket, @unchecked Sendable {
    
    let messageID: UInt16
    let reasonCodes: [MQTTUnsubAckReasonCode]
    let properties: MQTTAckProperties?
    
    init(header: MQTTPacketFixedHeader, networkData: Data, protocolVersion: MQTTProtocolVersion) {
        messageID = (UInt16(networkData[0]) * UInt16(256)) + UInt16(networkData[1])

        if protocolVersion == .v500,
           let (propertiesLength, consumed) = mqtt_decodeVariableInteger(from: networkData, at: 2) {
            let propertiesStart = 2 + consumed
            let propertiesEnd = min(propertiesStart + propertiesLength, networkData.count)
            properties = Self.decodeProperties(from: networkData.subdata(in: propertiesStart..<propertiesEnd))

            let reasonStart = propertiesEnd
            let bytes = reasonStart < networkData.count ? networkData[reasonStart..<networkData.count] : Data()
            reasonCodes = bytes.compactMap { MQTTUnsubAckReasonCode(rawValue: $0) }
        } else {
            properties = nil
            reasonCodes = []
        }

        super.init(header: header)
    }

    var hasFailure: Bool {
        reasonCodes.contains(where: { $0.isFailure })
    }

    private static func decodeProperties(from data: Data) -> MQTTAckProperties {
        var properties = MQTTAckProperties()
        var index = 0

        while index < data.count {
            let id = data[index]
            index += 1

            switch id {
            case 0x1F: // Reason String
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return properties }
                properties.reasonString = value
                index += consumed
            case 0x26: // User Property
                guard let (key, keyConsumed) = mqtt_readUTF8String(from: data, at: index) else { return properties }
                index += keyConsumed
                guard let (value, valueConsumed) = mqtt_readUTF8String(from: data, at: index) else { return properties }
                index += valueConsumed
                properties.userProperties[key] = value
            default:
                return properties
            }
        }

        return properties
    }
}
