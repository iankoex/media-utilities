//
//  GrayBackgroundRound.swift
//  
//
//  Created by Ian on 04/12/2022.
//

import SwiftUI

@available(iOS 15.0, macOS 12.0, *)
extension View {
    func grayBackgroundRound() -> some View {
        modifier(GrayBackgroundRound())
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct GrayBackgroundRound: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
