//
//  MQTTPingPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTPingPacket: MQTTPacket, @unchecked Sendable {
    
    init() {
        super.init(header: MQTTPacketFixedHeader(packetType: MQTTPacketType.pingReq, flags: 0))
    }
}
