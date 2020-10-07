//
//  MQTTPingResp.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

class MQTTPingResp: MQTTPacket {
    
    override init(header: MQTTPacketFixedHeader) {
        super.init(header: header)
    }
}
