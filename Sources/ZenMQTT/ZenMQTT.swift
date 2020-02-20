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
    private var sslContext: NIOSSLContext? = nil
    private let handler = MQTTHandler()
    private var repeatedTask: RepeatedTask? = nil

    private let host: String
    private let port: Int
    private let clientID: String
    private var autoreconnect: Bool
    private var username: String?
    private var password: String?
    private var keepAlive: UInt16 = 0
    private var lastWillMessage: MQTTPubMsg? = nil
    private var topics = [String: MQTTQoS]()
    public var onMessageReceived: MQTTMessageReceived? = nil
    public var onHandlerRemoved: MQTTHandlerRemoved? = nil
    public var onErrorCaught: MQTTErrorCaught? = nil

    
    public init(
        host: String,
        port: Int,
        clientID: String,
        reconnect: Bool,
        eventLoopGroup: EventLoopGroup)
    {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.autoreconnect = reconnect
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
        
        sslContext = try NIOSSLContext(configuration: config)
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
                if let sslContext = self.sslContext {
                    let sslClientHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                    return channel.pipeline.addHandler(sslClientHandler).flatMap { () -> EventLoopFuture<Void> in
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
    
    public func stop() -> EventLoopFuture<Void> {
        repeatedTask?.cancel()
        
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(MQTTSessionError.socketError)
        }
        
        channel.flush()
        return channel.close(mode: .all).map { () -> () in
            self.channel = nil
        }
    }
        
    private func send(promiseId: UInt16, packet: MQTTPacket) -> EventLoopFuture<Void> {
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(MQTTSessionError.socketError)
        }

        if promiseId > 0 {
            
            handler.promises.removeValue(forKey: promiseId)

            let promise = channel.eventLoop.makePromise(of: Void.self)
            handler.promises[promiseId] = promise
            
            return channel.writeAndFlush(packet).flatMap { () -> EventLoopFuture<Void> in
                promise.futureResult
            }
        } else {
            return channel.writeAndFlush(packet)
        }
    }
    
    public func reconnect(cleanSession: Bool, subscribe: Bool) -> EventLoopFuture<Void> {
        return start().flatMap { () -> EventLoopFuture<Void> in
            let connectPacket = MQTTConnectPacket(clientID: self.clientID, cleanSession: cleanSession, keepAlive: self.keepAlive)
            
            // Set Optional vars
            connectPacket.username = self.username
            connectPacket.password = self.password
            connectPacket.lastWillMessage = self.lastWillMessage
            
            return self.send(promiseId: 1, packet: connectPacket).map { () -> () in
                if subscribe {
                    self.resubscribe()
                }
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
        handler.handlerRemoved = {
            if let onHandlerRemoved = self.onHandlerRemoved {
                onHandlerRemoved()
            }

            if self.autoreconnect {
                self.stop().whenComplete { _ in
                    sleep(5)
                    self.reconnect(cleanSession: cleanSession, subscribe: true).whenComplete { _ in }
                }
            }
        }

        return reconnect(cleanSession: cleanSession, subscribe: false)
    }

    public func disconnect() -> EventLoopFuture<Void> {
        autoreconnect = false
        
        let disconnectPacket = MQTTDisconnectPacket()
        return send(promiseId: 0, packet: disconnectPacket).flatMap { () -> EventLoopFuture<Void> in
            self.stop()
        }
    }
        
    private func ping(time: TimeAmount) {
        repeatedTask?.cancel()
        
        guard let channel = channel, time.nanoseconds > 0 else { return }

        repeatedTask = channel.eventLoop.scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
            let mqttPingReq = MQTTPingPacket()
            return self.send(promiseId: 0, packet: mqttPingReq)
        }
    }
    
    fileprivate func resubscribe() {
        guard self.topics.count > 0 else { return }
        
        let msgID = nextMessageID()
        let subscribePacket = MQTTSubPacket(topics: self.topics, messageID: msgID)
        send(promiseId: msgID, packet: subscribePacket).whenComplete { _ in }
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
        for topic in topics {
            self.topics[topic.key] = topic.value
        }
        
        let msgID = nextMessageID()
        let subscribePacket = MQTTSubPacket(topics: topics, messageID: msgID)
        return send(promiseId: msgID, packet: subscribePacket)
    }

    public func unsubscribe(from topic: String) -> EventLoopFuture<Void> {
        return unsubscribe(from: [topic])
    }
    
    public func unsubscribe(from topics: [String]) -> EventLoopFuture<Void> {
        for topic in topics {
            self.topics.removeValue(forKey: topic)
        }
        
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
