//
//  ImageEditor.swift
//  
//
//  Created by Ian on 29/12/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 10.15, *)
public struct ImageEditor: View {
    @Binding var image: UnifiedImage?
    var aspectRatio: CGFloat
    var onCompletion: (Result<UnifiedImage, Error>) -> Void

    public var body: some View {
        VStack {
            Image(unifiedImage: image!)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
        }
    }
}
