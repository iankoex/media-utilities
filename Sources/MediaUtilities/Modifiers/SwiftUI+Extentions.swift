//
//  File.swift
//  
//
//  Created by Ian on 08/12/2022.
//

import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
extension View {
    @inlinable
    public func overlay<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        self.overlay(content())
    }
}
