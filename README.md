# ZenMQTT

### Getting Started

#### Adding a dependencies clause to your Package.swift

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenMQTT.git", from: "1.0.6")
]
```

#### Make client
```
import NIO
import ZenMQTT

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer { try! eventLoopGroup.syncShutdownGracefully() }

let mqtt = ZenMQTT(
    host: "test.mosquitto.org",
    port: 1883,
    clientID: "zen-mqtt-test",
    reconnect: true,
    eventLoopGroup: eventLoopGroup
)
try mqtt.addTLS(cert: "certificate.crt", key: "private.key")
mqtt.onMessageReceived = { message in
    print(message.stringRepresentation!)
}
mqtt.onHandlerRemoved = {
    print("Handler removed")
}
mqtt.onErrorCaught = { error in
    print(error.localizedDescription)
}

```

#### Connect to server
```
try mqtt.connect(cleanSession: true).wait()
```

#### Subscibe topic
```
try mqtt.subscribe(to: ["/topic/test1" : .atLeastOnce]).wait()
```

#### Unsubscibe topic
```
try mqtt.unsubscribe(from: "/topic/test1").wait()
```

#### Publish message
```
let message = MQTTPubMsg(topic: "/topic/test1", payload: "Hello World!".data(using: .utf8)!, retain: false, QoS: .atLeastOnce)
try mqtt.publish(message: message).wait()
```

#### Disconnect client
```
try mqtt.disconnect().wait()
```
