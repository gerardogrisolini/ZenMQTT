//
//  ZenMQTT.swift
//
//  Created by Gerardo Grisolini on 01/27/20.
//  Copyright © 2020 Gerardo Grisolini. All rights reserved.
//

import Foundation
@preconcurrency import NIO
@preconcurrency import NIOSSL

private actor AckStore {
    typealias AckContinuation = AsyncThrowingStream<Void, Error>.Continuation

    private var pending: [UInt16: AckContinuation] = [:]

    func register(id: UInt16, continuation: AckContinuation) {
        pending[id] = continuation
    }

    func succeed(id: UInt16) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.yield(())
        continuation.finish()
    }

    func fail(id: UInt16, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.finish(throwing: error)
    }

    func failAll(error: Error) {
        for continuation in pending.values {
            continuation.finish(throwing: error)
        }
        pending.removeAll()
    }
}

private actor OutboundQueue {
    struct PendingWrite: @unchecked Sendable {
        let packet: MQTTPacket
        let completion: CheckedContinuation<Void, Error>
    }

    private var writes: [PendingWrite] = []
    private var waiters: [CheckedContinuation<PendingWrite?, Never>] = []
    private var closedError: Error? = nil

    func enqueue(packet: MQTTPacket) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if let closedError {
                continuation.resume(throwing: closedError)
                return
            }

            let write = PendingWrite(packet: packet, completion: continuation)
            if let waiter = waiters.popLast() {
                waiter.resume(returning: write)
            } else {
                writes.append(write)
            }
        }
    }

    func next() async -> PendingWrite? {
        if !writes.isEmpty {
            return writes.removeFirst()
        }

        if closedError != nil {
            return nil
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish(error: Error) {
        guard closedError == nil else { return }
        closedError = error

        let pendingWrites = writes
        writes.removeAll()

        for write in pendingWrites {
            write.completion.resume(throwing: error)
        }

        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(returning: nil)
        }
    }
}

public final class ZenMQTT {

    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel? = nil
    private var sslContext: NIOSSLContext? = nil
    private var connectionTask: Task<Void, Never>? = nil
    private var pingTask: Task<Void, Never>? = nil
    private let ackStore = AckStore()
    private var outboundQueue = OutboundQueue()

    private let host: String
    private let port: Int
    private let clientID: String
    private var protocolVersion: MQTTProtocolVersion
    private var autoreconnect: Bool
    private var isShuttingDown = false
    private var username: String?
    private var password: String?
    private var connectProperties: MQTTConnectProperties?
    private var cleanSessionOnReconnect: Bool = true
    private var keepAlive: UInt16 = 0
    private var lastWillMessage: MQTTPubMsg? = nil
    private var topics = [String: MQTTQoS]()
    private var inboundQoS2Pending = Set<UInt16>()
    public var onMessageReceived: MQTTMessageReceived? = nil
    public var onHandlerRemoved: MQTTHandlerRemoved? = nil
    public var onErrorCaught: MQTTErrorCaught? = nil
    public private(set) var lastConnAckProperties: MQTTConnAckProperties? = nil
    public var onDisconnectReceived: MQTTDisconnectReceived? = nil
    public private(set) var lastDisconnectReasonCode: MQTTDisconnectReasonCode? = nil
    public private(set) var lastDisconnectProperties: MQTTDisconnectProperties? = nil
    public var onAuthReceived: MQTTAuthReceived? = nil

    public init(
        host: String,
        port: Int,
        clientID: String,
        reconnect: Bool,
        protocolVersion: MQTTProtocolVersion = .v311,
        eventLoopGroup: EventLoopGroup)
    {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.protocolVersion = protocolVersion
        self.autoreconnect = reconnect
        self.eventLoopGroup = eventLoopGroup
    }

    public func addTLS(cert: String, key: String) throws {
        let cert = try NIOSSLCertificate.fromPEMFile(cert)
        let key = try NIOSSLPrivateKey(file: key, format: .pem)

        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        config.certificateChain = [.certificate(cert.first!)]
        config.privateKey = .privateKey(key)

        sslContext = try NIOSSLContext(configuration: config)
    }

    public func addTLS(rootCert: String) throws {
        let certs = try NIOSSLCertificate.fromPEMFile(rootCert)

        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        config.trustRoots = .certificates(certs)

        sslContext = try NIOSSLContext(configuration: config)
    }

    private func start() async throws {
        let sslContext = self.sslContext
        let host = self.host
        let protocolVersion = self.protocolVersion

        let asyncChannel = try await ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .channelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(5))
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .channelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    var handlers: [ChannelHandler] = [
                        MessageToByteHandler(MQTTPacketEncoder()),
                        ByteToMessageHandler(MQTTPacketDecoder(protocolVersion: protocolVersion))
                    ]

                    if let sslContext {
                        let sslClientHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        handlers.insert(sslClientHandler, at: 0)
                    }

                    try channel.pipeline.syncOperations.addHandlers(handlers)

                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(inboundType: MQTTPacket.self, outboundType: MQTTPacket.self)
                    )
                }
            }

        self.channel = asyncChannel.channel
        self.outboundQueue = OutboundQueue()
        startConnectionLoop(asyncChannel: asyncChannel, outboundQueue: self.outboundQueue)
    }

    private func startConnectionLoop(asyncChannel: NIOAsyncChannel<MQTTPacket, MQTTPacket>, outboundQueue: OutboundQueue) {
        connectionTask?.cancel()

        connectionTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await asyncChannel.executeThenClose { inbound, outbound in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { [weak self] in
                            guard let self else { return }

                            for try await packet in inbound {
                                await self.handleInbound(packet: packet, outbound: outbound)
                            }

                            throw MQTTSessionError.socketError
                        }

                        group.addTask {
                            while let pendingWrite = await outboundQueue.next() {
                                do {
                                    try await outbound.write(pendingWrite.packet)
                                    pendingWrite.completion.resume(returning: ())
                                } catch {
                                    pendingWrite.completion.resume(throwing: error)
                                    throw error
                                }
                            }
                        }

                        _ = try await group.next()
                        group.cancelAll()
                    }
                }

                await self.handleSocketClosure(error: MQTTSessionError.socketError)
            } catch {
                await self.handleSocketClosure(error: error)
            }
        }
    }

    private func handleInbound(packet: MQTTPacket, outbound: NIOAsyncChannelOutboundWriter<MQTTPacket>) async {
        switch packet {
        case let connAckPacket as MQTTConnAckPacket:
            lastConnAckProperties = connAckPacket.properties
            if let serverKeepAlive = connAckPacket.properties?.serverKeepAlive {
                keepAlive = serverKeepAlive
            }
            if connAckPacket.response == .connectionAccepted {
                await ackStore.succeed(id: 1)
            } else {
                await ackStore.fail(id: 1, error: MQTTSessionError.connectionError(connAckPacket.response))
            }

        case let subAckPacket as MQTTSubAckPacket:
            if subAckPacket.hasFailure {
                let reason = subAckPacket.properties?.reasonString ?? "SUBACK failure (\(subAckPacket.reasonCodes.map { String(format: "0x%02X", $0.rawValue) }.joined(separator: ",")))"
                await ackStore.fail(id: subAckPacket.messageID, error: MQTTSessionError.ackError(reason))
            } else {
                await ackStore.succeed(id: subAckPacket.messageID)
            }

        case let unSubAckPacket as MQTTUnSubAckPacket:
            if unSubAckPacket.hasFailure {
                let reason = unSubAckPacket.properties?.reasonString ?? "UNSUBACK failure (\(unSubAckPacket.reasonCodes.map { String(format: "0x%02X", $0.rawValue) }.joined(separator: ",")))"
                await ackStore.fail(id: unSubAckPacket.messageID, error: MQTTSessionError.ackError(reason))
            } else {
                await ackStore.succeed(id: unSubAckPacket.messageID)
            }

        case let pubAck as MQTTPubAck:
            if pubAck.reasonCode.isFailure {
                let reason = pubAck.properties?.reasonString ?? "PUBACK failure (0x\(String(format: "%02X", pubAck.reasonCode.rawValue)))"
                await ackStore.fail(id: pubAck.messageID, error: MQTTSessionError.ackError(reason))
            } else {
                await ackStore.succeed(id: pubAck.messageID)
            }

        case let pubRec as MQTTPubRecPacket:
            if pubRec.reasonCode.isFailure {
                let reason = pubRec.properties?.reasonString ?? "PUBREC failure (0x\(String(format: "%02X", pubRec.reasonCode.rawValue)))"
                await ackStore.fail(id: pubRec.messageID, error: MQTTSessionError.ackError(reason))
            } else {
                do {
                    try await outbound.write(MQTTPubRelPacket(messageID: pubRec.messageID, protocolVersion: protocolVersion))
                } catch {
                    await ackStore.fail(id: pubRec.messageID, error: error)
                }
            }

        case let pubRel as MQTTPubRelPacket:
            if inboundQoS2Pending.contains(pubRel.messageID) {
                inboundQoS2Pending.remove(pubRel.messageID)
            }
            do {
                try await outbound.write(MQTTPubCompPacket(messageID: pubRel.messageID, protocolVersion: protocolVersion))
            } catch {
                onErrorCaught?(error)
            }

        case let pubComp as MQTTPubCompPacket:
            if pubComp.reasonCode.isFailure {
                let reason = pubComp.properties?.reasonString ?? "PUBCOMP failure (0x\(String(format: "%02X", pubComp.reasonCode.rawValue)))"
                await ackStore.fail(id: pubComp.messageID, error: MQTTSessionError.ackError(reason))
            } else {
                await ackStore.succeed(id: pubComp.messageID)
            }

        case let publishPacket as MQTTPublishPacket:
            if publishPacket.messageID > 0 {
                do {
                    if publishPacket.message.QoS == .exactlyOnce {
                        inboundQoS2Pending.insert(publishPacket.messageID)
                        try await outbound.write(MQTTPubRecPacket(messageID: publishPacket.messageID, protocolVersion: protocolVersion))
                    } else {
                        try await outbound.write(MQTTPubAck(messageID: publishPacket.messageID, protocolVersion: protocolVersion))
                    }
                } catch {
                    onErrorCaught?(error)
                }
            }

            if let messageReceived = onMessageReceived {
                messageReceived(MQTTMessage(publishPacket: publishPacket))
            }

        case let disconnectPacket as MQTTDisconnectPacket:
            lastDisconnectReasonCode = disconnectPacket.reasonCode
            lastDisconnectProperties = disconnectPacket.properties
            onDisconnectReceived?(disconnectPacket.reasonCode, disconnectPacket.properties)
            do {
                if let channel {
                    try await channel.close(mode: .all).get()
                }
            } catch {
                onErrorCaught?(error)
            }

        case let authPacket as MQTTAuthPacket:
            onAuthReceived?(authPacket.reasonCode, authPacket.properties)

        default:
            break
        }
    }

    private func handleSocketClosure(error: Error) async {
        let shuttingDown = isShuttingDown

        pingTask?.cancel()
        await outboundQueue.finish(error: error)
        await ackStore.failAll(error: error)

        channel = nil
        connectionTask = nil
        isShuttingDown = false

        if !shuttingDown {
            onErrorCaught?(error)
        }

        onHandlerRemoved?()

        guard autoreconnect, !shuttingDown else { return }

        eventLoopGroup.next().scheduleTask(in: .seconds(3)) { [weak self] in
            guard let self else { return }
            Task {
                try? await self.reconnect(cleanSession: self.cleanSessionOnReconnect, subscribe: true)
            }
        }
    }

    public func stop() async throws {
        guard let channel else {
            throw MQTTSessionError.socketError
        }

        isShuttingDown = true
        pingTask?.cancel()
        await outboundQueue.finish(error: MQTTSessionError.socketError)

        try await channel.close(mode: .all).get()
        connectionTask?.cancel()
        await connectionTask?.value
        connectionTask = nil
        self.channel = nil
    }

    private func send(promiseId: UInt16, packet: MQTTPacket) async throws {
        guard channel != nil else {
            throw MQTTSessionError.socketError
        }

        if promiseId == 0 {
            try await outboundQueue.enqueue(packet: packet)
            return
        }

        var continuation: AsyncThrowingStream<Void, Error>.Continuation!
        let ackStream = AsyncThrowingStream<Void, Error> { continuation = $0 }

        await ackStore.register(id: promiseId, continuation: continuation)

        do {
            try await outboundQueue.enqueue(packet: packet)
        } catch {
            await ackStore.fail(id: promiseId, error: error)
            throw error
        }

        var iterator = ackStream.makeAsyncIterator()
        _ = try await iterator.next()
    }

    public func reconnect(cleanSession: Bool, subscribe: Bool) async throws {
        try await start()

        let connectPacket = MQTTConnectPacket(
            clientID: clientID,
            cleanSession: cleanSession,
            keepAlive: keepAlive,
            protocolVersion: protocolVersion,
            connectProperties: connectProperties
        )
        connectPacket.username = username
        connectPacket.password = password
        connectPacket.lastWillMessage = lastWillMessage

        try await send(promiseId: 1, packet: connectPacket)

        if subscribe {
            await resubscribe()
        }

        ping()
    }

    public func connect(
        username: String? = nil,
        password: String? = nil,
        cleanSession: Bool = true,
        keepAlive: UInt16 = 0,
        protocolVersion: MQTTProtocolVersion? = nil,
        connectProperties: MQTTConnectProperties? = nil
    ) async throws {
        self.username = username
        self.password = password
        self.cleanSessionOnReconnect = cleanSession
        self.keepAlive = keepAlive
        self.connectProperties = connectProperties
        if let protocolVersion {
            self.protocolVersion = protocolVersion
        }

        try await reconnect(cleanSession: cleanSession, subscribe: false)
    }

    public func disconnect() async throws {
        autoreconnect = false

        try await send(promiseId: 0, packet: MQTTDisconnectPacket(protocolVersion: protocolVersion))
        try await stop()
    }

    public func auth(
        reasonCode: MQTTAuthReasonCode = .success,
        properties: MQTTAuthProperties? = nil
    ) async throws {
        guard protocolVersion == .v500 else {
            throw MQTTSessionError.ackError("AUTH is only supported in MQTT 5.0")
        }
        try await send(promiseId: 0, packet: MQTTAuthPacket(reasonCode: reasonCode, properties: properties))
    }

    private func ping() {
        pingTask?.cancel()

        guard keepAlive > 0 else { return }

        let interval = UInt64(keepAlive) * 1_000_000_000
        pingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                    try await self.send(promiseId: 0, packet: MQTTPingPacket())
                } catch {
                    return
                }
            }
        }
    }

    private func resubscribe() async {
        guard !topics.isEmpty else { return }

        let msgID = nextMessageID()
        let subscribePacket = MQTTSubPacket(topics: topics, messageID: msgID, protocolVersion: protocolVersion)
        try? await send(promiseId: msgID, packet: subscribePacket)
    }

    public func publish(message: MQTTPubMsg) async throws {
        let msgID = nextMessageID()
        let publishPacket = MQTTPublishPacket(messageID: msgID, message: message, protocolVersion: protocolVersion)
        try await send(promiseId: msgID, packet: publishPacket)
    }

    public func subscribe(to topic: String, delivering qos: MQTTQoS) async throws {
        try await subscribe(to: [topic: qos])
    }

    public func subscribe(to topics: [String: MQTTQoS]) async throws {
        for topic in topics {
            self.topics[topic.key] = topic.value
        }

        let msgID = nextMessageID()
        let subscribePacket = MQTTSubPacket(topics: topics, messageID: msgID, protocolVersion: protocolVersion)
        try await send(promiseId: msgID, packet: subscribePacket)
    }

    public func unsubscribe(from topic: String) async throws {
        try await unsubscribe(from: [topic])
    }

    public func unsubscribe(from topics: [String]) async throws {
        for topic in topics {
            self.topics.removeValue(forKey: topic)
        }

        let msgID = nextMessageID()
        let unSubPacket = MQTTUnsubPacket(topics: topics, messageID: msgID, protocolVersion: protocolVersion)
        try await send(promiseId: msgID, packet: unSubPacket)
    }

    private var messageID = UInt16(1)

    private func nextMessageID() -> UInt16 {
        messageID += 1
        return messageID
    }
}

extension MQTTPacket: @unchecked Sendable {}
extension ZenMQTT: @unchecked Sendable {}
