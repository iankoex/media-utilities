//
//  WidthObtainingBackgroundView.swift
//  Items
//
//  Created by Ian on 24/06/2022.
//

import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
struct WidthObtainingBackgroundView: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
//            withAnimation {
//                width = proxy.size.width
//            }
             Color.clear
                .onAppear {
                    width = proxy.size.width
                }
        }
    }
}
