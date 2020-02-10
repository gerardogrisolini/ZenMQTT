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
    private var channel: Channel? = nil
    private var sslClientHandler: NIOSSLClientHandler? = nil
    private let handler = MQTTHandler()
    
    private let host: String
    private let port: Int
    private let clientID: String
    private var autoReconnect: Bool
    private var username: String?
    private var password: String?
    private var keepAlive: UInt16 = 0
    private var lastWillMessage: MQTTPubMsg? = nil
    public var onMessageReceived: MQTTMessageReceived? = nil
    public var onHandlerRemoved: MQTTHandlerRemoved? = nil
    public var onErrorCaught: MQTTErrorCaught? = nil

    public init(
        host: String,
        port: Int,
        clientID: String,
        autoReconnect: Bool,
        eventLoopGroup: EventLoopGroup)
    {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.autoReconnect = autoReconnect
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
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(MQTTSessionError.socketError)
        }
        
        channel.flush()
        return channel.close(mode: .all)
    }
        
    private func send(promiseId: UInt16, packet: MQTTPacket) -> EventLoopFuture<Void> {
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(MQTTSessionError.socketError)
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
    
    fileprivate func startAndConnect(cleanSession: Bool) -> EventLoopFuture<Void> {
        return start().flatMap { () -> EventLoopFuture<Void> in
            let connectPacket = MQTTConnectPacket(clientID: self.clientID, cleanSession: cleanSession, keepAlive: self.keepAlive)
            
            // Set Optional vars
            connectPacket.username = self.username
            connectPacket.password = self.password
            connectPacket.lastWillMessage = self.lastWillMessage
            
            return self.send(promiseId: 1, packet: connectPacket).map { () -> () in
                self.ping(time: TimeAmount.seconds(Int64(self.keepAlive)))
            }
        }
    }
    
    public func connect(username: String? = nil, password: String? = nil, cleanSession: Bool = true, keepAlive: UInt16 = 0) -> EventLoopFuture<Void> {
        self.username = username
        self.password = password
        self.keepAlive = keepAlive

        handler.messageReceived = onMessageReceived
        handler.errorCaught = onErrorCaught
//        handler.handlerRemoved = {
//            if let onHandlerRemoved = self.onHandlerRemoved {
//                onHandlerRemoved()
//            }
//            if self.autoReconnect {
//                self.autoReconnect = false
//                self.stop().whenComplete { _ in
//                    self.startAndConnect(cleanSession: false).whenComplete { _ in }
//                }
//            }
//        }
        handler.handlerRemoved = onHandlerRemoved

        return startAndConnect(cleanSession: cleanSession)
    }

    public func disconnect() -> EventLoopFuture<Void> {
        autoReconnect = false
        
        let disconnectPacket = MQTTDisconnectPacket()
        return send(promiseId: 0, packet: disconnectPacket).flatMap { () -> EventLoopFuture<Void> in
            return self.stop()
        }
    }
        
    private func ping(time: TimeAmount) {
        if time.nanoseconds == 0 { return }
        
        eventLoopGroup.next().scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
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
