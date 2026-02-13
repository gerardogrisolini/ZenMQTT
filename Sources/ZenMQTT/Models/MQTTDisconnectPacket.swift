//
//  MQTTDisconnectPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTDisconnectPacket: MQTTPacket, @unchecked Sendable {
    let protocolVersion: MQTTProtocolVersion
    let reasonCode: MQTTDisconnectReasonCode
    let properties: MQTTDisconnectProperties?

    init(
        protocolVersion: MQTTProtocolVersion,
        reasonCode: MQTTDisconnectReasonCode = .normalDisconnection,
        properties: MQTTDisconnectProperties? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.reasonCode = reasonCode
        self.properties = properties
        super.init(header: MQTTPacketFixedHeader(packetType: .disconnect, flags: 0))
    }

    override func variableHeader() -> Data {
        guard protocolVersion == .v500 else { return Data() }

        var variableHeader = Data()
        variableHeader.mqtt_append(reasonCode.rawValue)

        var props = Data()
        if let sessionExpiryInterval = properties?.sessionExpiryInterval {
            props.mqtt_append(UInt8(0x11))
            props.mqtt_append(sessionExpiryInterval)
        }
        if let reasonString = properties?.reasonString {
            props.mqtt_append(UInt8(0x1F))
            props.mqtt_append(reasonString)
        }
        if let serverReference = properties?.serverReference {
            props.mqtt_append(UInt8(0x1C))
            props.mqtt_append(serverReference)
        }
        if let userProperties = properties?.userProperties {
            for (key, value) in userProperties {
                props.mqtt_append(UInt8(0x26))
                props.mqtt_append(key)
                props.mqtt_append(value)
            }
        }

        variableHeader.mqtt_appendVariableInteger(props.count)
        variableHeader.append(props)
        return variableHeader
    }

    init(header: MQTTPacketFixedHeader, networkData: Data, protocolVersion: MQTTProtocolVersion) {
        self.protocolVersion = protocolVersion

        guard protocolVersion == .v500 else {
            self.reasonCode = .normalDisconnection
            self.properties = nil
            super.init(header: header)
            return
        }

        if networkData.isEmpty {
            self.reasonCode = .normalDisconnection
            self.properties = MQTTDisconnectProperties()
            super.init(header: header)
            return
        }

        self.reasonCode = MQTTDisconnectReasonCode(rawValue: networkData[0]) ?? .unspecifiedError

        guard networkData.count > 1,
              let (propertiesLength, consumed) = mqtt_decodeVariableInteger(from: networkData, at: 1) else {
            self.properties = MQTTDisconnectProperties()
            super.init(header: header)
            return
        }

        let propertiesStart = 1 + consumed
        let propertiesEnd = min(propertiesStart + propertiesLength, networkData.count)
        self.properties = Self.decodeProperties(from: networkData.subdata(in: propertiesStart..<propertiesEnd))
        super.init(header: header)
    }

    private static func decodeProperties(from data: Data) -> MQTTDisconnectProperties {
        var props = MQTTDisconnectProperties()
        var index = 0

        while index < data.count {
            let id = data[index]
            index += 1

            switch id {
            case 0x11:
                guard let value = mqtt_readUInt32(from: data, at: index) else { return props }
                props.sessionExpiryInterval = value
                index += 4
            case 0x1F:
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                props.reasonString = value
                index += consumed
            case 0x1C:
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                props.serverReference = value
                index += consumed
            case 0x26:
                guard let (key, keyConsumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                index += keyConsumed
                guard let (value, valueConsumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                index += valueConsumed
                props.userProperties[key] = value
            default:
                return props
            }
        }

        return props
    }
}
