import Foundation

final class MQTTAuthPacket: MQTTPacket, @unchecked Sendable {
    let reasonCode: MQTTAuthReasonCode
    let properties: MQTTAuthProperties?

    init(reasonCode: MQTTAuthReasonCode = .success, properties: MQTTAuthProperties? = nil) {
        self.reasonCode = reasonCode
        self.properties = properties
        super.init(header: MQTTPacketFixedHeader(packetType: .auth, flags: 0))
    }

    override func variableHeader() -> Data {
        var data = Data()

        let hasProperties = !(properties?.userProperties.isEmpty ?? true)
            || properties?.authenticationMethod != nil
            || properties?.authenticationData != nil
            || properties?.reasonString != nil

        if reasonCode != .success || hasProperties {
            data.mqtt_append(reasonCode.rawValue)

            var props = Data()
            if let method = properties?.authenticationMethod {
                props.mqtt_append(UInt8(0x15))
                props.mqtt_append(method)
            }
            if let authData = properties?.authenticationData {
                props.mqtt_append(UInt8(0x16))
                props.mqtt_append(authData)
            }
            if let reasonString = properties?.reasonString {
                props.mqtt_append(UInt8(0x1F))
                props.mqtt_append(reasonString)
            }
            if let userProperties = properties?.userProperties {
                for (key, value) in userProperties {
                    props.mqtt_append(UInt8(0x26))
                    props.mqtt_append(key)
                    props.mqtt_append(value)
                }
            }

            data.mqtt_appendVariableInteger(props.count)
            data.append(props)
        }

        return data
    }

    init(header: MQTTPacketFixedHeader, networkData: Data) {
        if networkData.isEmpty {
            self.reasonCode = .success
            self.properties = MQTTAuthProperties()
            super.init(header: header)
            return
        }

        self.reasonCode = MQTTAuthReasonCode(rawValue: networkData[0]) ?? .success

        guard networkData.count > 1,
              let (propertiesLength, consumed) = mqtt_decodeVariableInteger(from: networkData, at: 1) else {
            self.properties = MQTTAuthProperties()
            super.init(header: header)
            return
        }

        let start = 1 + consumed
        let end = min(start + propertiesLength, networkData.count)
        self.properties = Self.decodeProperties(from: networkData.subdata(in: start..<end))
        super.init(header: header)
    }

    private static func decodeProperties(from data: Data) -> MQTTAuthProperties {
        var props = MQTTAuthProperties()
        var index = 0

        while index < data.count {
            let id = data[index]
            index += 1

            switch id {
            case 0x15: // Authentication Method
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                props.authenticationMethod = value
                index += consumed
            case 0x16: // Authentication Data
                guard let (value, consumed) = mqtt_readBinaryData(from: data, at: index) else { return props }
                props.authenticationData = value
                index += consumed
            case 0x1F: // Reason String
                guard let (value, consumed) = mqtt_readUTF8String(from: data, at: index) else { return props }
                props.reasonString = value
                index += consumed
            case 0x26: // User Property
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
