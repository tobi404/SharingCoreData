//
//  UnsafeSendableValue.swift
//  sharing-core-data
//
//  Created by Beka Demuradze on 18.02.26.
//

/// Internal escape hatch for crossing async boundaries with main-actor-confined Core Data values.
/// Values wrapped here must never be accessed off the actor that produced them.
struct UnsafeSendableValue<Value>: @unchecked Sendable {
    let value: Value
}
