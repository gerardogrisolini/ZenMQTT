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
    private let protocolVersion: MQTTProtocolVersion

    public init(protocolVersion: MQTTProtocolVersion = .v311) {
        self.protocolVersion = protocolVersion
    }

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState  {
        guard buffer.readableBytes >= 2 else { return .needMoreData }

        let (count, remainingLength) = try buffer.getRemainingLength(at: buffer.readerIndex + 1)
        guard buffer.readableBytes >= (1 + Int(count) + remainingLength) else { return .needMoreData }

        if let packet = parse(&buffer) {
            context.fireChannelRead(self.wrapInboundOut(packet))
            return .continue
        }
        return .needMoreData
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }

    func parse(_ buffer: inout ByteBuffer) -> MQTTPacket? {
        var body = Data()
        let headerByte: UInt8 = buffer.getInteger(at: buffer.readerIndex)!
        let header = MQTTPacketFixedHeader(networkByte: headerByte)
        buffer.moveReaderIndex(forwardBy: 1)
        
        guard let (count, remainingLength) = try? buffer.getRemainingLength(at: buffer.readerIndex) else { return nil }
        buffer.moveReaderIndex(forwardBy: Int(count))
        
        if remainingLength > 0 {
            let bytes = buffer.getBytes(at: buffer.readerIndex, length: remainingLength)!
            body.append(contentsOf: bytes)
            buffer.moveReaderIndex(forwardBy: remainingLength)
        }
        
        switch header.packetType {
            case .connAck:
                return MQTTConnAckPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .subAck:
                return MQTTSubAckPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .unSubAck:
                return MQTTUnSubAckPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .pubAck:
                return MQTTPubAck(header: header, networkData: body, protocolVersion: protocolVersion)
            case .pubRec:
                return MQTTPubRecPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .pubRel:
                return MQTTPubRelPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .pubComp:
                return MQTTPubCompPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .publish:
                return MQTTPublishPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .pingResp:
                return MQTTPingResp(header: header)
            case .disconnect:
                return MQTTDisconnectPacket(header: header, networkData: body, protocolVersion: protocolVersion)
            case .auth:
                return MQTTAuthPacket(header: header, networkData: body)
            default:
                return nil
        }
    }
}

extension ByteBuffer {
    /*
     Lunghezza rimanente

     Il secondo byte dell'intestazione fissa contiene la lunghezza rimanente che è la lunghezza dell'intestazione variabile + la lunghezza del carico utile. La lunghezza rimanente può utilizzare fino a 4 byte in cui ogni byte utilizza 7 bit per la lunghezza e il bit MSB è un flag di continuazione.
     se il bit di flag di continuazione di un byte è 1, significa che anche il byte successivo fa parte della lunghezza rimanente. E se il bit del flag di continuazione è 0, significa che il byte è l'ultimo della lunghezza rimanente.

     Per esempio. se la lunghezza variabile dell'intestazione è 10 e la lunghezza del carico utile è 20, la lunghezza rimanente dovrebbe essere 30.
     */
    
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
        } while ((byte & 128) != 0)

        return (count: UInt8(currentIndex - newReaderIndex), length: value)
    }
}

public enum RemainingLengthError: Error {
    case incomplete
    case malformed
}
