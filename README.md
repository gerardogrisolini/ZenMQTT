# ZenMQTT

Swift MQTT client based on SwiftNIO with async/await API.

## Features

- Swift 6.2
- Async/await public API
- MQTT 3.1.1 and MQTT 5.0
- QoS 0/1/2 publish flow
- TLS support (client cert/key or root CA)
- MQTT 5 properties support for:
  - CONNECT / CONNACK
  - PUBLISH
  - SUBACK / UNSUBACK
  - PUBACK / PUBREC / PUBREL / PUBCOMP
  - DISCONNECT
  - AUTH

## Installation

Add dependency in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenMQTT.git", from: "1.0.6")
]
```

## Quick Start

```swift
import NIO
import ZenMQTT

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer { try! eventLoopGroup.syncShutdownGracefully() }

let mqtt = ZenMQTT(
    host: "test.mosquitto.org",
    port: 1883,
    clientID: "zen-mqtt-test",
    reconnect: true,
    protocolVersion: .v311,
    eventLoopGroup: eventLoopGroup
)

mqtt.onMessageReceived = { message in
    print(message.stringRepresentation ?? "<binary>")
}

mqtt.onHandlerRemoved = {
    print("Handler removed")
}

mqtt.onErrorCaught = { error in
    print(error.localizedDescription)
}

try await mqtt.connect(cleanSession: true, keepAlive: 30)
try await mqtt.subscribe(to: ["/topic/test1": .atLeastOnce])

let message = MQTTPubMsg(
    topic: "/topic/test1",
    payload: "Hello World!".data(using: .utf8)!,
    retain: false,
    QoS: .atLeastOnce
)
try await mqtt.publish(message: message)

try await mqtt.unsubscribe(from: "/topic/test1")
try await mqtt.disconnect()
```

## TLS

Client certificate + key:

```swift
try mqtt.addTLS(cert: "client.crt", key: "client.key")
```

Root CA only:

```swift
try mqtt.addTLS(rootCert: "ca.crt")
```

## MQTT 5.0 Usage

Create client with MQTT 5:

```swift
let mqtt = ZenMQTT(
    host: "test.mosquitto.org",
    port: 8884,
    clientID: "zen-mqtt-v5",
    reconnect: true,
    protocolVersion: .v500,
    eventLoopGroup: eventLoopGroup
)
```

Connect with MQTT 5 CONNECT properties:

```swift
let connectProps = MQTTConnectProperties(
    sessionExpiryInterval: 60,
    receiveMaximum: 20,
    maximumPacketSize: 1_048_576,
    topicAliasMaximum: 10
)

try await mqtt.connect(
    cleanSession: true,
    keepAlive: 30,
    protocolVersion: .v500,
    connectProperties: connectProps
)
```

Publish with MQTT 5 PUBLISH properties:

```swift
let publishProps = MQTTPublishProperties(
    payloadFormatIndicator: 1,
    messageExpiryInterval: 60,
    contentType: "text/plain",
    responseTopic: "reply/topic",
    correlationData: "corr-1".data(using: .utf8),
    topicAlias: 1
)

let msg = MQTTPubMsg(
    topic: "demo/topic",
    payload: "hello".data(using: .utf8)!,
    retain: false,
    QoS: .exactlyOnce,
    properties: publishProps
)

try await mqtt.publish(message: msg)
```

## MQTT 5 Events

Disconnect callback:

```swift
mqtt.onDisconnectReceived = { reason, properties in
    print("DISCONNECT reason: \(reason)")
    print("reason string: \(properties?.reasonString ?? "-")")
}
```

AUTH callback:

```swift
mqtt.onAuthReceived = { reason, properties in
    print("AUTH reason: \(reason)")
    print("method: \(properties?.authenticationMethod ?? "-")")
}
```

Send AUTH packet:

```swift
let authProps = MQTTAuthProperties(
    authenticationMethod: "SCRAM-SHA-256",
    authenticationData: Data([0x01, 0x02])
)

try await mqtt.auth(reasonCode: .continue, properties: authProps)
```
