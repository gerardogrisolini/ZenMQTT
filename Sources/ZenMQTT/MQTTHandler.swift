//
//  MQTTHandler.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

public typealias MQTTReceiver = (MQTTMessage) -> ()

final class MQTTHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    private var receiver: MQTTReceiver? = nil
    public var promises = Dictionary<UInt16, EventLoopPromise<Void>>()
    public var isConnected: Bool

    public init() {
        isConnected = false
    }
    
    func setReceiver(receiver: @escaping MQTTReceiver) {
        self.receiver = receiver
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        print("MQTT Client connected to \(context.remoteAddress!)")
        isConnected = true
    }
        
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        
        if let packet = parse(buffer) {
            switch packet {
            case let connAckPacket as MQTTConnAckPacket:
                if let promise = promises[1] {
                    if connAckPacket.response == .connectionAccepted {
                        promise.succeed(())
                    } else {
                        promise.fail(MQTTSessionError.connectionError(connAckPacket.response))
                    }
                    promises.removeValue(forKey: 1)
                }
            case let subAckPacket as MQTTSubAckPacket:
                if let promise = promises[subAckPacket.messageID] {
                    promise.succeed(())
                    promises.removeValue(forKey: subAckPacket.messageID)
                }
            case let unSubAckPacket as MQTTUnSubAckPacket:
                if let promise = promises[unSubAckPacket.messageID] {
                    promise.succeed(())
                    promises.removeValue(forKey: unSubAckPacket.messageID)
                }
            case let pubAck as MQTTPubAck:
                if let promise = promises[pubAck.messageID] {
                    promise.succeed(())
                    promises.removeValue(forKey: pubAck.messageID)
                }
            case let publishPacket as MQTTPublishPacket:
                sendPubAck(for: publishPacket.messageID, context: context)
                let message = MQTTMessage(publishPacket: publishPacket)
                receiver?(message)
            default:
                if let response = String(bytes: packet.payload(), encoding: .utf8) {
                    print(response)
                }
            }
        }
//        else if let bytes = buffer.getBytes(at: 0, length: buffer.readableBytes),
//            let response = String(bytes: bytes, encoding: .utf8) {
//            print(response)
//        }
    }
    
    func parse(_ buffer: ByteBuffer) -> MQTTPacket? {
        var headerByte: UInt8 = 0
        headerByte = buffer.getBytes(at: 0, length: 1)![0]
        let len = buffer.getBytes(at: 1, length: 1)![0]
        guard len > 0 else { return nil }

        let header = MQTTPacketFixedHeader(networkByte: headerByte)
        let body = Data(buffer.getBytes(at: 2, length: buffer.readableBytes - 2)!)
        
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
    
    private func sendPubAck(for messageId: UInt16, context: ChannelHandlerContext) {
        let pubAck = MQTTPubAck(messageID: messageId)
        var buffer = context.channel.allocator.buffer(capacity: pubAck.networkPacket().count)
        buffer.writeBytes(pubAck.networkPacket())
        context.channel.writeAndFlush(buffer, promise: nil)
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        print("MQTT Client disconnected from \(context.remoteAddress!)")
        isConnected = false
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        // As we are not really interested getting notified on success or failure
        // we just pass nil as promise to reduce allocations.
        context.close(promise: nil)
    }
}
