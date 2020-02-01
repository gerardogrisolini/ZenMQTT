//
//  MQTTPacketEncoder.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import NIO

public final class MQTTPacketEncoder: MessageToByteEncoder {
    public typealias OutboundIn = MQTTPacket

    public func encode(data value: MQTTPacket, out: inout ByteBuffer) throws {
        out.clear()
        out.reserveCapacity(value.networkPacket().count)
        out.writeBytes(value.networkPacket())
    }
}
