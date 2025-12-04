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

    /// Requests camera access permission from the user.
    ///
    /// This method prompts the user for camera access permission if it hasn't
    /// been determined yet. The permission dialog will only be shown once,
    /// subsequent calls will return the current permission status.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// await cameraService.requestCameraAccess()
    /// let status = cameraService.authorizationStatus
    /// if status == .authorized {
    ///     print("Camera access granted")
    /// }
    /// ```
    ///
    /// - Note: This method should be called before attempting to use the camera.
    @concurrent
    public func requestCameraAccess() async {
        guard authorizationStatus == .notDetermined else {
            print("Camera access already authorized")
            return
        }
        sessionQueue.suspend()
        _ = await AVCaptureDevice.requestAccess(for: .video)
        sessionQueue.resume()
    }
}
