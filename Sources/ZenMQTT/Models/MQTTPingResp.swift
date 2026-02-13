//
//  MQTTPingResp.swift
//
//
//  Created by Gerardo Grisolini on 01/02/2020.
//

import Foundation

final class MQTTPingResp: MQTTPacket, @unchecked Sendable {
    
    override init(header: MQTTPacketFixedHeader) {
        super.init(header: header)
    }
}
