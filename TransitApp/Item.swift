//
//  Item.swift
//  TransitApp
//
//  Created by Henry Lam on 2/5/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
