//
//  ZenMQTT.swift
//  ZenMQTT
//
//  Created by Gerardo Grisolini on 01/27/20.
//  Copyright © 2020 Gerardo Grisolini. All rights reserved.
//

import Foundation
import NIO
import NIOSSL


public class ZenMQTT {
	
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel!
    private var sslClientHandler: NIOSSLClientHandler? = nil
    private let handler = MQTTHandler()
    
    public let host: String
    public let port: Int
    public let clientID: String
    public let cleanSession: Bool
    public var lastWillMessage: MQTTPubMsg?
    public var onMessageReceived: MQTTMessageReceived? = nil
    public var onHandlerRemoved: MQTTHandlerRemoved? = nil
    public var onErrorCaught: MQTTErrorCaught? = nil

    public init(
        host: String,
        port: Int,
        clientID: String,
        cleanSession: Bool,
        eventLoopGroup: EventLoopGroup)
    {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.cleanSession = cleanSession
        self.eventLoopGroup = eventLoopGroup
    }

    public func addTLS(cert: String, key: String) throws {
        let cert = try NIOSSLCertificate.fromPEMFile(cert)
        let key = try NIOSSLPrivateKey.init(file: key, format: .pem)
        
        let config = TLSConfiguration.forClient(
            certificateVerification: .none,
            certificateChain: [.certificate(cert.first!)],
            privateKey: .privateKey(key)
        )
        
        let sslContext = try NIOSSLContext(configuration: config)
        sslClientHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
    }

    private func start() -> EventLoopFuture<Void> {
        
        handler.messageReceived = onMessageReceived
        handler.handlerRemoved = onHandlerRemoved
        handler.errorCaught = onErrorCaught

        let handlers: [ChannelHandler] = [
            MessageToByteHandler(MQTTPacketEncoder()),
            ByteToMessageHandler(MQTTPacketDecoder()),
            handler
        ]
        
        return ClientBootstrap(group: eventLoopGroup)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelInitializer { channel in
                if let ssl = self.sslClientHandler {
                    return channel.pipeline.addHandler(ssl).flatMap { () -> EventLoopFuture<Void> in
                        channel.pipeline.addHandlers(handlers)
                    }
                } else {
                    return channel.pipeline.addHandlers(handlers)
                }
            }
            .connect(host: host, port: port)
            .map { channel -> () in
                self.channel = channel
            }
    }
    
    private func stop() -> EventLoopFuture<Void> {
        channel.flush()
        return channel.close(mode: .all)
    }
        
    private func send(promiseId: UInt16, packet: MQTTPacket) -> EventLoopFuture<Void> {
        if !channel.isActive {
            return channel.eventLoop.makeFailedFuture(MQTTSessionError.socketError)
        }
        
        if promiseId > 0 {
            let promise = channel.eventLoop.makePromise(of: Void.self)
            handler.promises[promiseId] = promise
            
            return channel.writeAndFlush(packet).flatMap { () -> EventLoopFuture<Void> in
                promise.futureResult
            }
        } else {
            return channel.writeAndFlush(packet)
        }
    }
    
    public func connect(username: String? = nil, password: String? = nil, keepAlive: UInt16 = 0) -> EventLoopFuture<Void> {
        return start().flatMap { () -> EventLoopFuture<Void> in
            let connectPacket = MQTTConnectPacket(clientID: self.clientID, cleanSession: self.cleanSession, keepAlive: keepAlive)
            
            // Set Optional vars
            connectPacket.username = username
            connectPacket.password = password
            connectPacket.lastWillMessage = self.lastWillMessage

            return self.send(promiseId: 1, packet: connectPacket).map { () -> () in
                self.ping(time: TimeAmount.seconds(Int64(keepAlive)))
            }
        }
    }

    public func disconnect() -> EventLoopFuture<Void> {
        let disconnectPacket = MQTTDisconnectPacket()
        return send(promiseId: 0, packet: disconnectPacket).flatMap { () -> EventLoopFuture<Void> in
            return self.stop()
        }
    }
        
    private func ping(time: TimeAmount) {
        if time.nanoseconds == 0 { return }
        
        channel.eventLoop.scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
            let mqttPingReq = MQTTPingPacket()
            return self.send(promiseId: 0, packet: mqttPingReq)
        }
    }
    
    public func publish(message: MQTTPubMsg) -> EventLoopFuture<Void> {
        let msgID = nextMessageID()
        let publishPacket = MQTTPublishPacket(messageID: msgID, message: message)
        return send(promiseId: msgID, packet: publishPacket)
    }

    public func subscribe(to topic: String, delivering qos: MQTTQoS) -> EventLoopFuture<Void> {
        return subscribe(to: [topic: qos])
    }
    
    public func subscribe(to topics: [String: MQTTQoS]) -> EventLoopFuture<Void> {
        let msgID = nextMessageID()
        let subscribePacket = MQTTSubPacket(topics: topics, messageID: msgID)
        return send(promiseId: msgID, packet: subscribePacket)
    }

    public func unsubscribe(from topic: String) -> EventLoopFuture<Void> {
        return unsubscribe(from: [topic])
    }
    
    public func unsubscribe(from topics: [String]) -> EventLoopFuture<Void> {
        let msgID = nextMessageID()
        let unSubPacket = MQTTUnsubPacket(topics: topics, messageID: msgID)
        return send(promiseId: msgID, packet: unSubPacket)
    }
    
    private var messageID = UInt16(1)
    
    private func nextMessageID() -> UInt16 {
        messageID += 1
        return messageID
    }
}
