import Foundation

final class MQTTPubCompPacket: MQTTPacket, @unchecked Sendable {
    let messageID: UInt16
    let protocolVersion: MQTTProtocolVersion
    let reasonCode: MQTTPubCompReasonCode
    let properties: MQTTPubAckProperties?

    init(
        messageID: UInt16,
        protocolVersion: MQTTProtocolVersion,
        reasonCode: MQTTPubCompReasonCode = .success,
        properties: MQTTPubAckProperties? = nil
    ) {
        self.messageID = messageID
        self.protocolVersion = protocolVersion
        self.reasonCode = reasonCode
        self.properties = properties
        super.init(header: MQTTPacketFixedHeader(packetType: .pubComp, flags: 0))
    }

    override func variableHeader() -> Data {
        var data = Data()
        data.mqtt_append(messageID)

        if protocolVersion == .v500 {
            let hasProperties = !(properties?.userProperties.isEmpty ?? true) || properties?.reasonString != nil
            if reasonCode != .success || hasProperties {
                data.mqtt_append(reasonCode.rawValue)
                var props = Data()
                if let reasonString = properties?.reasonString {
                    props.mqtt_append(UInt8(0x1F))
                    props.mqtt_append(reasonString)
                }
                if let userProperties = properties?.userProperties {
                    for (k, v) in userProperties {
                        props.mqtt_append(UInt8(0x26))
                        props.mqtt_append(k)
                        props.mqtt_append(v)
                    }
                }
                data.mqtt_appendVariableInteger(props.count)
                data.append(props)
            }
        }

        return data
    }

    init(header: MQTTPacketFixedHeader, networkData: Data, protocolVersion: MQTTProtocolVersion) {
        self.protocolVersion = protocolVersion
        self.messageID = (UInt16(networkData[0]) * UInt16(256)) + UInt16(networkData[1])
        if protocolVersion == .v500, networkData.count > 2 {
            self.reasonCode = MQTTPubCompReasonCode(rawValue: networkData[2]) ?? .packetIdentifierNotFound
            if networkData.count > 3,
               let (len, consumed) = mqtt_decodeVariableInteger(from: networkData, at: 3) {
                let start = 3 + consumed
                let end = min(start + len, networkData.count)
                self.properties = Self.decodeProperties(from: networkData.subdata(in: start..<end))
            } else {
                self.properties = MQTTPubAckProperties()
            }
        } else {
            self.reasonCode = .success
            self.properties = nil
        }
        super.init(header: header)
    }

    private static func decodeProperties(from data: Data) -> MQTTPubAckProperties {
        var props = MQTTPubAckProperties()
        var index = 0

        while index < data.count {
            let id = data[index]
            index += 1
            switch id {
            case 0x1F:
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                props.reasonString = value
                index += consumed
            case 0x26:
                guard let (k, c1) = mqtt_readUTF8String(from: data, at: index) else { return props }
                index += c1
                guard let (v, c2) = mqtt_readUTF8String(from: data, at: index) else { return props }
                index += c2
                props.userProperties[k] = v
            default:
                return props
            }
        }
        return props
    }
}
