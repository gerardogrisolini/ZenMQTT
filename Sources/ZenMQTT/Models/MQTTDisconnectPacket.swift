//
//  MQTTDisconnectPacket.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

class MQTTDisconnectPacket: MQTTPacket {
    
    init() {
        super.init(header: MQTTPacketFixedHeader(packetType: .disconnect, flags: 0))
    }
}
