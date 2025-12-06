//
//  CameraCaptureViewModifier.swift
//  MediaUtilities
//
//  Created by ian on 04/12/2025.
//

import SwiftUI

// MARK: - Camera Capture View Modifier

@available(iOS 14.0, macOS 11, *)
extension View {
    /// Presents a full-screen camera capture interface as a modal overlay.
    ///
    /// This modifier provides a convenient way to present the `CameraCaptureView`
    /// as a full-screen modal with automatic dismissal handling. It wraps the
    /// camera interface in a platform-appropriate presentation and manages the presentation state.
    ///
    /// The modifier handles:
    /// - Modal presentation and dismissal
    /// - Camera initialization and cleanup
    /// - Result propagation to the provided closure
    /// - Automatic state management for presentation binding
    ///
    /// ## Usage
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @State private var showCamera = false
    ///
    ///     var body: some View {
    ///         VStack {
    ///             Button("Open Camera") {
    ///                 showCamera = true
    ///             }
    ///         }
    ///         .cameraCapture(isPresented: $showCamera) { result in
    ///             switch result {
    ///             case .success(let url):
    ///                 print("Photo/video saved to: \(url)")
    ///             case .failure(let error):
    ///                 print("Camera error: \(error)")
    ///             }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Platform Availability
    ///
    /// - iOS 14.0+
    /// - macOS 11.0+
    ///
    /// ## Parameters
    ///
    /// - isPresented: A binding that controls the modal presentation state.
    ///   When set to `true`, the camera interface appears. When set to `false`,
    ///   it disappears. The binding is automatically set to `false` when the
    ///   camera interface is dismissed.
    /// - onCapture: A closure that handles the result of camera operations.
    ///   Called when a photo is captured or video recording completes,
    ///   providing either the media URL or an error.
    ///
    /// - Returns: A view that presents the camera capture interface as a modal.
    public func cameraCapture(
        isPresented: Binding<Bool>,
        onCapture: @escaping (Result<URL, CameraError>) -> Void
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            CameraCaptureView(onCapture: { result in
                isPresented.wrappedValue = false
                onCapture(result)
            })
        }
        #else
        // On macOS, use sheet presentation instead of fullScreenCover
        sheet(isPresented: isPresented) {
            CameraCaptureView(onCapture: { result in
                isPresented.wrappedValue = false
                onCapture(result)
            })
        }
        #endif
    }
}
