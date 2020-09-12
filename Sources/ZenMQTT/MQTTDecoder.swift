//
//  MQTTPacketDecoder.swift
//  
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation
import NIO

public final class MQTTPacketDecoder: ByteToMessageDecoder {
    public typealias InboundOut = MQTTPacket

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState  {
        guard buffer.readableBytes >= 2 else { return .needMoreData }

        let (count, remainingLength) = try buffer.getRemainingLength(at: buffer.readerIndex + 1)
        guard buffer.readableBytes >= (1 + Int(count) + remainingLength) else { return .needMoreData }

        if let packet = parse(buffer) {
            context.fireChannelRead(self.wrapInboundOut(packet))
            context.fireChannelReadComplete()
            buffer.clear()
            return .continue
        } else {
            return .needMoreData
        }
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        // EOF is not semantic in WebSocket, so ignore this.
        return .needMoreData
    }

    func parse(_ buffer: ByteBuffer) -> MQTTPacket? {
        var headerByte: UInt8 = 0
        headerByte = buffer.getBytes(at: 0, length: 1)![0]
        
        guard let len = buffer.readPackedLength() else { return nil }

        let header = MQTTPacketFixedHeader(networkByte: headerByte)
        let body = Data(buffer.getBytes(at: buffer.readableBytes - len, length: len)!)
        
        switch header.packetType {
            case .connAck:
                return MQTTConnAckPacket(header: header, networkData: body)
            case .subAck:
                return MQTTSubAckPacket(header: header, networkData: body)
            case .unSubAck:
                return MQTTUnSubAckPacket(header: header, networkData: body)
            case .pubRec, .pubAck:
                return MQTTPubAck(header: header, networkData: body)
            case .publish:
                return MQTTPublishPacket(header: header, networkData: body)
            case .pingResp:
                return MQTTPingResp(header: header)
            default:
                return nil
        }
    }
}

extension ByteBuffer {
    func getRemainingLength(at newReaderIndex: Int) throws -> (count: UInt8, length: Int) {
        var multiplier: UInt32 = 1
        var value: Int = 0
        var byte: UInt8 = 0
        var currentIndex = newReaderIndex
        repeat {
            guard currentIndex != (readableBytes + 1) else { throw RemainingLengthError.incomplete }

            guard multiplier <= (128 * 128 * 128) else { throw RemainingLengthError.malformed }

            guard let nextByte: UInt8 = getInteger(at: currentIndex) else { throw RemainingLengthError.incomplete }

            byte = nextByte

            value += Int(UInt32(byte & 127) * multiplier)
            multiplier *= 128
            currentIndex += 1
        } while ((byte & 128) != 0)// && !isEmpty

        return (count: UInt8(currentIndex - newReaderIndex), length: value)
    }

    func readPackedLength() -> Int? {
        var multiplier = 1
        var length = 0
        var encodedByte: UInt8 = 0
        var index = 1
        repeat {
            //let _ = read(&encodedByte, 1)
            encodedByte = getBytes(at: index, length: 1)![0]
            index += 1
            length += (Int(encodedByte) & 127) * multiplier
            multiplier *= 128
            if multiplier > 128*128*128 {
                return nil
            }
        } while ((Int(encodedByte) & 128) != 0)
        return length <= 128*128*128 ? length : nil
    }
}

public enum RemainingLengthError: Error {
    case incomplete
    case malformed
}
