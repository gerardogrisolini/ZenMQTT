import Foundation

public typealias MQTTMessageReceived = (MQTTMessage) -> ()
public typealias MQTTHandlerRemoved = () -> ()
public typealias MQTTErrorCaught = (Error) -> ()
public typealias MQTTDisconnectReceived = (MQTTDisconnectReasonCode, MQTTDisconnectProperties?) -> ()
public typealias MQTTAuthReceived = (MQTTAuthReasonCode, MQTTAuthProperties?) -> ()
