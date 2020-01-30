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
    public var keepAlive: UInt16 = 0
    public var onMessage: MQTTReceiver = { _ in }

    public var lastWillMessage: MQTTPubMsg?
    public var isConnected: Bool { return handler.isConnected }

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

    public func start(keepAlive: UInt16 = 0) -> EventLoopFuture<Void> {
        self.keepAlive = keepAlive
        
        handler.setReceiver(receiver: onMessage)
        
        return ClientBootstrap(group: eventLoopGroup)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelInitializer { channel in
                if let ssl = self.sslClientHandler {
                    return channel.pipeline.addHandler(ssl).flatMap { () -> EventLoopFuture<Void> in
                        channel.pipeline.addHandler(self.handler)
                    }
                } else {
                    return channel.pipeline.addHandler(self.handler)
                }
            }
            .connect(host: host, port: port)
            .map { channel -> () in
                self.channel = channel
                if keepAlive > 0 {
                    self.ping(time: TimeAmount.seconds(Int64(keepAlive)))
                }
            }
    }
    
    public func stop() -> EventLoopFuture<Void> {
        channel.flush()
        return channel.close()
    }
        
    private func send(promiseId: UInt16, packet: MQTTPacket) -> EventLoopFuture<Void> {
        var buffer = channel.allocator.buffer(capacity: packet.networkPacket().count)
        buffer.writeBytes(packet.networkPacket())

        if promiseId > 0 {
            let promise = channel.eventLoop.makePromise(of: Void.self)
            handler.promises[promiseId] = promise
            
            return channel.writeAndFlush(buffer).flatMap { () -> EventLoopFuture<Void> in
                promise.futureResult
            }
        } else {
            return channel.writeAndFlush(buffer)
        }
    }
    
    
    public func connect(username: String? = nil, password: String? = nil) -> EventLoopFuture<Void> {
        let connectPacket = MQTTConnectPacket(clientID: clientID, cleanSession: cleanSession, keepAlive: keepAlive)
        
        // Set Optional vars
        connectPacket.username = username
        connectPacket.password = password
        connectPacket.lastWillMessage = lastWillMessage

        return send(promiseId: 1, packet: connectPacket)
    }

    public func disconnect() -> EventLoopFuture<Void> {
        let disconnectPacket = MQTTDisconnectPacket()
        return send(promiseId: 0, packet: disconnectPacket)
    }
    
    private func ping(time: TimeAmount) {
        channel.eventLoop.scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
            let mqttPingReq = MQTTPingPacket()
            return self.send(promiseId: 0, packet: mqttPingReq)
        }
    }
    
    public func publish(_ data: Data, in topic: String, delivering qos: MQTTQoS, retain: Bool) -> EventLoopFuture<Void> {
        let msgID = nextMessageID()
        let pubMsg = MQTTPubMsg(topic: topic, payload: data, retain: retain, QoS: qos)
        let publishPacket = MQTTPublishPacket(messageID: msgID, message: pubMsg)
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
