//
//  MQTTHandler.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

public typealias MQTTMessageReceived = (MQTTMessage) -> ()
public typealias MQTTHandlerRemoved = (Bool) -> ()

final class MQTTHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = MQTTPacket
    public typealias OutboundOut = MQTTPacket
    
    private var isConnected: Bool = false
    public var messageReceived: MQTTMessageReceived? = nil
    public var handlerRemoved: MQTTHandlerRemoved? = nil
    public var promises = Dictionary<UInt16, EventLoopPromise<Void>>()

    public init() {
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        debugPrint("MQTT Client connected to \(context.remoteAddress!)")
        isConnected = true
    }
        
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = self.unwrapInboundIn(data)
        
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
            guard let messageReceived = messageReceived else { return }
            let message = MQTTMessage(publishPacket: publishPacket)
            messageReceived(message)
            
            let pubAck = MQTTPubAck(messageID: publishPacket.messageID)
            context.write(self.wrapOutboundOut(pubAck), promise: nil)
        default:
            if let payload = String(bytes: packet.payload(), encoding: .utf8) {
                debugPrint(payload)
            }
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        debugPrint("MQTT handler removed.")
        guard let handlerRemoved = handlerRemoved else { return }
        handlerRemoved(isConnected)
        isConnected = false
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        debugPrint("MQTT handler error: ", error)
        // As we are not really interested getting notified on success or failure
        // we just pass nil as promise to reduce allocations.
        context.close(promise: nil)
    }
}
