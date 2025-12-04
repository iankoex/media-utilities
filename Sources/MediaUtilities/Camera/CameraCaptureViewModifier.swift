//
//  CameraCaptureViewModifier.swift
//  MediaUtilities
//
//  Created by ian on 04/12/2025.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
extension View {
    public func cameraCapture(
        isPresented: Binding<Bool>,
        onCapture: @escaping (Result<URL, CameraError>) -> Void
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            CameraCaptureView(onCapture: { result in
                isPresented.wrappedValue = false
                onCapture(result)
            })
        }
    }
}
