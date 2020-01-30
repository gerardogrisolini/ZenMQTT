# ZenMQTT

### Getting Started

#### Adding a dependencies clause to your Package.swift

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenMQTT.git", from: "1.0.0")
]
```

#### Make client
```
import ZenMQTT

let mqtt = ZenMQTT(host: "test.mosquitto.org", port: 1883)
try mqtt.addTLS(cert: "certificate.crt", key: "private.key")
mqtt.onMessage = { message in
    print(message.stringRepresentation!)
}
```

#### Start client
```
try mqtt.start().wait()
```

#### Connect to server
```
try mqtt.connect(username: "admin", password: "123456789").wait()
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
try mqtt.publish(
    "Hello World!".data(using: .utf8)!,
    in: "/topic/test1" ,
    delivering: .atLeastOnce,
    retain: false
).wait()
```

#### Disconnect client
```
try mqtt.disconnect().wait()
```

#### Stop client
```
try mqtt.stop().wait()
```
