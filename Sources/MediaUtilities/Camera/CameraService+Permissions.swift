//
//  CameraService+Permissions.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

// MARK: - Permission Handling

@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Requests camera and microphone access permissions from the user.
    ///
    /// This method prompts the user for both camera and microphone access permissions
    /// if they haven't been determined yet. Both permissions are requested concurrently
    /// for a unified permission experience. The permission dialogs will only be shown once,
    /// subsequent calls will return the current permission statuses.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// await cameraService.requestCameraAccess()
    /// let cameraStatus = cameraService.authorizationStatus
    /// let micStatus = cameraService.microphoneAuthorizationStatus
    /// if cameraStatus == .authorized && micStatus == .authorized {
    ///     // Both permissions granted
    /// }
    /// ```
    ///
    /// - Note: This method should be called before attempting to use camera features that require audio.
    @concurrent
    public func requestCameraAccess() async {
        // Request both video and audio permissions concurrently
        async let videoPermission = AVCaptureDevice.requestAccess(for: .video)
        async let audioPermission = AVCaptureDevice.requestAccess(for: .audio)

        // Wait for both permission requests to complete
        _ = await (videoPermission, audioPermission)
    }
}
