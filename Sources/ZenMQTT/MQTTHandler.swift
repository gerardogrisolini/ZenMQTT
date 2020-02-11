//
//  MQTTHandler.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

public typealias MQTTMessageReceived = (MQTTMessage) -> ()
public typealias MQTTHandlerRemoved = () -> ()
public typealias MQTTErrorCaught = (Error) -> ()

final class MQTTHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = MQTTPacket
    public typealias OutboundOut = MQTTPacket
    
    public var messageReceived: MQTTMessageReceived? = nil
    public var handlerRemoved: MQTTHandlerRemoved? = nil
    public var errorCaught: MQTTErrorCaught? = nil
    public var promises = Dictionary<UInt16, EventLoopPromise<Void>>()
    private var isReconnect: Bool = false
    
    public init() {
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        debugPrint("MQTT Client connected to \(context.remoteAddress!)")
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
            if publishPacket.messageID > 0 {
                let pubAck = MQTTPubAck(messageID: publishPacket.messageID)
                context.writeAndFlush(self.wrapOutboundOut(pubAck), promise: nil)
            }
            if let messageReceived = messageReceived {
                let message = MQTTMessage(publishPacket: publishPacket)
                messageReceived(message)
            }
        default:
            break
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        isReconnect = true
        
        guard let handlerRemoved = handlerRemoved else { return }
        handlerRemoved()
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)

        guard let errorCaught = errorCaught else { return }
        errorCaught(error)
    }
}
