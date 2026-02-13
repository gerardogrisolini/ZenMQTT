//
//  MQTT+Extension.swift
//
//  Created by Gerardo Grisolini on 01/27/20.
//  Copyright © 2020 Gerardo Grisolini. All rights reserved.
//
import Foundation

public enum MQTTSessionError: Error {
    case none
    case socketError
    case connectionError(MQTTConnAckResponse)
    case ackError(String)
    case streamError(Error?)
}

enum MQTTPacketType: UInt8 {
    case connect        = 0x01
    case connAck        = 0x02
    case publish        = 0x03
    case pubAck         = 0x04
    case pubRec         = 0x05
    case pubRel         = 0x06
    case pubComp        = 0x07
    case subscribe      = 0x08
    case subAck         = 0x09
    case unSubscribe    = 0x0A
    case unSubAck       = 0x0B
    case pingReq        = 0x0C
    case pingResp       = 0x0D
    case disconnect     = 0x0E
    case auth           = 0x0F
}

public enum MQTTQoS: UInt8 {
    case atMostOnce     = 0x0
    case atLeastOnce    = 0x01
    case exactlyOnce    = 0x02
}

public enum MQTTProtocolVersion: UInt8, Sendable {
    case v311 = 0x04
    case v500 = 0x05
}

public struct MQTTConnectProperties: Sendable {
    public var sessionExpiryInterval: UInt32?
    public var receiveMaximum: UInt16?
    public var maximumPacketSize: UInt32?
    public var topicAliasMaximum: UInt16?

    public init(
        sessionExpiryInterval: UInt32? = nil,
        receiveMaximum: UInt16? = nil,
        maximumPacketSize: UInt32? = nil,
        topicAliasMaximum: UInt16? = nil
    ) {
        self.sessionExpiryInterval = sessionExpiryInterval
        self.receiveMaximum = receiveMaximum
        self.maximumPacketSize = maximumPacketSize
        self.topicAliasMaximum = topicAliasMaximum
    }
}

public struct MQTTConnAckProperties: Sendable {
    public var sessionExpiryInterval: UInt32?
    public var receiveMaximum: UInt16?
    public var maximumPacketSize: UInt32?
    public var topicAliasMaximum: UInt16?
    public var serverKeepAlive: UInt16?

    public init(
        sessionExpiryInterval: UInt32? = nil,
        receiveMaximum: UInt16? = nil,
        maximumPacketSize: UInt32? = nil,
        topicAliasMaximum: UInt16? = nil,
        serverKeepAlive: UInt16? = nil
    ) {
        self.sessionExpiryInterval = sessionExpiryInterval
        self.receiveMaximum = receiveMaximum
        self.maximumPacketSize = maximumPacketSize
        self.topicAliasMaximum = topicAliasMaximum
        self.serverKeepAlive = serverKeepAlive
    }
}

public struct MQTTPublishProperties: Sendable {
    public var payloadFormatIndicator: UInt8?
    public var messageExpiryInterval: UInt32?
    public var contentType: String?
    public var responseTopic: String?
    public var correlationData: Data?
    public var topicAlias: UInt16?

    public init(
        payloadFormatIndicator: UInt8? = nil,
        messageExpiryInterval: UInt32? = nil,
        contentType: String? = nil,
        responseTopic: String? = nil,
        correlationData: Data? = nil,
        topicAlias: UInt16? = nil
    ) {
        self.payloadFormatIndicator = payloadFormatIndicator
        self.messageExpiryInterval = messageExpiryInterval
        self.contentType = contentType
        self.responseTopic = responseTopic
        self.correlationData = correlationData
        self.topicAlias = topicAlias
    }
}

public struct MQTTAckProperties: Sendable {
    public var reasonString: String?
    public var userProperties: [String: String]

    public init(reasonString: String? = nil, userProperties: [String: String] = [:]) {
        self.reasonString = reasonString
        self.userProperties = userProperties
    }
}

public struct MQTTDisconnectProperties: Sendable {
    public var sessionExpiryInterval: UInt32?
    public var reasonString: String?
    public var serverReference: String?
    public var userProperties: [String: String]

    public init(
        sessionExpiryInterval: UInt32? = nil,
        reasonString: String? = nil,
        serverReference: String? = nil,
        userProperties: [String: String] = [:]
    ) {
        self.sessionExpiryInterval = sessionExpiryInterval
        self.reasonString = reasonString
        self.serverReference = serverReference
        self.userProperties = userProperties
    }
}

public struct MQTTPubAckProperties: Sendable {
    public var reasonString: String?
    public var userProperties: [String: String]

    public init(reasonString: String? = nil, userProperties: [String: String] = [:]) {
        self.reasonString = reasonString
        self.userProperties = userProperties
    }
}

public enum MQTTPubAckReasonCode: UInt8, Sendable {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTPubRecReasonCode: UInt8, Sendable {
    case success = 0x00
    case noMatchingSubscribers = 0x10
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicNameInvalid = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTPubRelReasonCode: UInt8, Sendable {
    case success = 0x00
    case packetIdentifierNotFound = 0x92

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTPubCompReasonCode: UInt8, Sendable {
    case success = 0x00
    case packetIdentifierNotFound = 0x92

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTDisconnectReasonCode: UInt8, Sendable {
    case normalDisconnection = 0x00
    case disconnectWithWillMessage = 0x04
    case unspecifiedError = 0x80
    case malformedPacket = 0x81
    case protocolError = 0x82
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case serverBusy = 0x89
    case serverShuttingDown = 0x8B
    case keepAliveTimeout = 0x8D
    case sessionTakenOver = 0x8E
    case topicFilterInvalid = 0x8F
    case topicNameInvalid = 0x90
    case receiveMaximumExceeded = 0x93
    case topicAliasInvalid = 0x94
    case packetTooLarge = 0x95
    case messageRateTooHigh = 0x96
    case quotaExceeded = 0x97
    case administrativeAction = 0x98
    case payloadFormatInvalid = 0x99
    case retainNotSupported = 0x9A
    case qosNotSupported = 0x9B
    case useAnotherServer = 0x9C
    case serverMoved = 0x9D
    case sharedSubscriptionsNotSupported = 0x9E
    case connectionRateExceeded = 0x9F
    case maximumConnectTime = 0xA0
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2

    public var isError: Bool { rawValue >= 0x80 }
}

public struct MQTTAuthProperties: Sendable {
    public var authenticationMethod: String?
    public var authenticationData: Data?
    public var reasonString: String?
    public var userProperties: [String: String]

    public init(
        authenticationMethod: String? = nil,
        authenticationData: Data? = nil,
        reasonString: String? = nil,
        userProperties: [String: String] = [:]
    ) {
        self.authenticationMethod = authenticationMethod
        self.authenticationData = authenticationData
        self.reasonString = reasonString
        self.userProperties = userProperties
    }
}

public enum MQTTAuthReasonCode: UInt8, Sendable {
    case success = 0x00
    case `continue` = 0x18
    case reAuthenticate = 0x19
}

public enum MQTTSubAckReasonCode: UInt8, Sendable {
    case grantedQoS0 = 0x00
    case grantedQoS1 = 0x01
    case grantedQoS2 = 0x02
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91
    case quotaExceeded = 0x97
    case sharedSubscriptionsNotSupported = 0x9E
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTUnsubAckReasonCode: UInt8, Sendable {
    case success = 0x00
    case noSubscriptionExisted = 0x11
    case unspecifiedError = 0x80
    case implementationSpecificError = 0x83
    case notAuthorized = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUse = 0x91

    public var isFailure: Bool { rawValue >= 0x80 }
}

public enum MQTTConnAckResponse: UInt8, Error {
    case connectionAccepted     = 0x00
    case badProtocol            = 0x01
    case clientIDRejected       = 0x02
    case serverUnavailable      = 0x03
    case badUsernameOrPassword  = 0x04
    case notAuthorized          = 0x05
    // MQTT 5 reason codes
    case unspecifiedError           = 0x80
    case malformedPacket            = 0x81
    case protocolError              = 0x82
    case implementationSpecificError = 0x83
    case unsupportedProtocolVersion = 0x84
    case clientIdentifierNotValid   = 0x85
    case badAuthenticationMethod    = 0x8C
    case topicNameInvalid           = 0x90
    case packetTooLarge             = 0x95
    case quotaExceeded              = 0x97
    case payloadFormatInvalid       = 0x99
    case retainNotSupported         = 0x9A
    case qosNotSupported            = 0x9B
    case useAnotherServer           = 0x9C
    case serverMoved                = 0x9D
    case connectionRateExceeded     = 0x9F
}

extension Data {
    mutating func mqtt_encodeRemaining(length: Int) {
        var lengthOfRemainingData = length
        repeat {
            var digit = UInt8(lengthOfRemainingData % 128)
            lengthOfRemainingData /= 128
            if lengthOfRemainingData > 0 {
                digit |= 0x80
            }
            append(&digit, count: 1)
        } while lengthOfRemainingData > 0
    }
    
    mutating func mqtt_append(_ data: UInt8) {
        var varData = data
        append(&varData, count: 1)
    }
    
    // Appends two bytes
    // Big Endian
    mutating func mqtt_append(_ data: UInt16) {
        let byteOne = UInt8(data / 256)
        let byteTwo = UInt8(data % 256)
        mqtt_append(byteOne)
        mqtt_append(byteTwo)
    }

    mutating func mqtt_append(_ data: UInt32) {
        mqtt_append(UInt8((data >> 24) & 0xFF))
        mqtt_append(UInt8((data >> 16) & 0xFF))
        mqtt_append(UInt8((data >> 8) & 0xFF))
        mqtt_append(UInt8(data & 0xFF))
    }
    
    mutating func mqtt_append(_ data: Data) {
        mqtt_append(UInt16(data.count))
        append(data)
    }
    
    mutating func mqtt_append(_ string: String) {
        mqtt_append(UInt16(string.count))
        append(string.data(using: .utf8)!)
    }

    mutating func mqtt_appendVariableInteger(_ value: Int) {
        mqtt_encodeRemaining(length: value)
    }
}

func mqtt_decodeVariableInteger(from data: Data, at offset: Int) -> (value: Int, consumed: Int)? {
    var multiplier = 1
    var value = 0
    var consumed = 0
    var index = offset

    while index < data.count && consumed < 4 {
        let encodedByte = Int(data[index])
        value += (encodedByte & 0x7F) * multiplier
        consumed += 1
        index += 1

        if (encodedByte & 0x80) == 0 {
            return (value, consumed)
        }

        multiplier *= 128
    }

    return nil
}

func mqtt_readUInt16(from data: Data, at offset: Int) -> UInt16? {
    guard offset + 1 < data.count else { return nil }
    return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

func mqtt_readUInt32(from data: Data, at offset: Int) -> UInt32? {
    guard offset + 3 < data.count else { return nil }
    return (UInt32(data[offset]) << 24)
        | (UInt32(data[offset + 1]) << 16)
        | (UInt32(data[offset + 2]) << 8)
        | UInt32(data[offset + 3])
}

func mqtt_readUTF8String(from data: Data, at offset: Int) -> (value: String, consumed: Int)? {
    guard let length = mqtt_readUInt16(from: data, at: offset) else { return nil }
    let start = offset + 2
    let end = start + Int(length)
    guard end <= data.count else { return nil }
    guard let value = String(data: data.subdata(in: start..<end), encoding: .utf8) else { return nil }
    return (value, 2 + Int(length))
}

func mqtt_readBinaryData(from data: Data, at offset: Int) -> (value: Data, consumed: Int)? {
    guard let length = mqtt_readUInt16(from: data, at: offset) else { return nil }
    let start = offset + 2
    let end = start + Int(length)
    guard end <= data.count else { return nil }
    return (data.subdata(in: start..<end), 2 + Int(length))
}

extension MQTTSessionError: Equatable {
    public static func ==(lhs: MQTTSessionError, rhs: MQTTSessionError) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none), (.socketError, .socketError):
            return true
        case (.connectionError(let lhsResponse), .connectionError(let rhsResponse)):
            return lhsResponse == rhsResponse
        case (.ackError(let lhsReason), .ackError(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}

extension MQTTSessionError: CustomStringConvertible {

    public var description: String {

        switch self {
        case .none:
            return "None"
        case .socketError:
            return "Socket Error"
        case .ackError(let reason):
            return "ACK Error: \(reason)"
        case .streamError:
            return "Stream Error"
        case .connectionError(let response):
            return "Connection Error: \(response.localizedDescription)"
        }
    }

    public var localizedDescription: String {
        return description
    }
}
