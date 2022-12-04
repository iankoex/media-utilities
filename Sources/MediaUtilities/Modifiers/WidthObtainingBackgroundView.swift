//
//  WidthObtainingBackgroundView.swift
//  Items
//
//  Created by Ian on 24/06/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
struct WidthObtainingBackgroundView: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    width = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _ in
                    withAnimation {
                        width = proxy.size.width
                    }
                }
        }
    }
}
