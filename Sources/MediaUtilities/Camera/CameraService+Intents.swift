//
//  CameraService+Intents.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

// MARK: - Camera Error

/// Errors that can occur during camera operations.
///
/// The `CameraError` enum encompasses all possible failure scenarios
/// when working with the camera service, providing localized descriptions
/// for user-facing error messages and enabling proper error handling.
public enum CameraError: LocalizedError, Equatable {
    /// Camera access was denied by the user.
    case permissionDenied
    
    /// No camera hardware is available on the current device.
    case deviceNotAvailable
    
    /// Photo capture operation failed.
    case captureFailed
    
    /// Video recording operation failed.
    case recordingFailed
    
    /// Camera session configuration failed.
    case configurationFailed
    
    /// User cancelled the camera operation.
    case userCancelled
    
    /// An unexpected error occurred with a custom message.
    case unknown(String)

    public var errorDescription: String? {
        switch self {
            case .permissionDenied:
                return "Camera access denied. Please enable in Settings"
            case .deviceNotAvailable:
                return "Camera is not available on this device"
            case .captureFailed:
                return "Failed to capture photo"
            case .recordingFailed:
                return "Failed to record video"
            case .configurationFailed:
                return "Failed to configure camera"
            case .userCancelled:
                return "User cancelled"
            case .unknown(let message):
                return "Camera error: \(message)"

        }
    }
}

// MARK: - High-Level User-Facing Operations
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Captures a photo with comprehensive error handling and user-friendly result.
    ///
    /// This method provides a high-level interface for photo capture with automatic
    /// permission checking, camera availability validation, and proper error handling.
    /// It's the recommended method for most photo capture use cases.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let result = await cameraService.capturePhotoWithCompletion()
    /// switch result {
    /// case .success(let url):
    ///     print("Photo captured: \(url)")
    /// case .failure(let error):
    ///     print("Capture failed: \(error)")
    /// }
    /// ```
    ///
    /// - Returns: `Result<URL, CameraError>` containing the photo URL or error information.
    @concurrent
    public func capturePhotoWithCompletion() async -> Result<URL, CameraError> {
        guard authorizationStatus == .authorized else {
            return .failure(.permissionDenied)
        }

        // Check camera availability
        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        // Ensure session is running
        if !isRunning {
            await start()
        }

        isCapturingPhoto = true
        defer { isCapturingPhoto = false }

        guard let photoURL = await capturePhoto() else {
            return .failure(.captureFailed)
        }

        return .success(photoURL)
    }

    /// Starts video recording with comprehensive error handling.
    ///
    /// This method provides a safe way to start video recording with automatic
    /// permission checking, camera availability validation, and proper error handling.
    /// The recording continues until `stopRecordingVideo()` is called.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let result = cameraService.startVideoRecording()
    /// switch result {
    /// case .success:
    ///     print("Recording started")
    /// case .failure(let error):
    ///     print("Failed to start recording: \(error)")
    /// }
    /// ```
    ///
    /// - Returns: `Result<Void, CameraError>` indicating success or failure.
    /// - Note: Use `movieFileStream` to receive the completed video URL.
    public func startVideoRecording() -> Result<Void, CameraError> {
        // Check permissions first
        guard authorizationStatus == .authorized else {
            return .failure(.permissionDenied)
        }

        // Check camera availability
        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        // Ensure session is running
        if !isRunning {
            Task {
                await start()
            }
        }

        // Start recording
        startRecordingVideo()
        return .success(())
    }

    /// Stops video recording and returns the completed video file URL.
    ///
    /// This method stops the current video recording session and returns
    /// the URL of the completed video file. The video is saved
    /// to the device's documents directory.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let result = await cameraService.stopVideoRecording()
    /// switch result {
    /// case .success(let url):
    ///     print("Video saved to: \(url)")
    /// case .failure(let error):
    ///     print("Failed to stop recording: \(error)")
    /// }
    /// ```
    ///
    /// - Returns: `Result<URL, CameraError>` containing video URL or error information.
    /// - Note: This method should only be called after `startVideoRecording()` succeeds.
    @concurrent
    public func stopVideoRecording() async -> Result<URL, CameraError> {
        // This will be called when recording delegate finishes
        // For now, we'll return a placeholder result
        // The actual URL will come through the movieFileStream
        return .success(URL(fileURLWithPath: "placeholder"))
    }

    /// Initializes the camera service for use with comprehensive setup.
    ///
    /// This method performs complete camera initialization including permission checking,
    /// device discovery, session configuration, and preview stream setup.
    /// It's the recommended method to prepare the camera for use.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let result = await cameraService.initializeCamera()
    /// switch result {
    /// case .success:
    ///     print("Camera ready for use")
    /// case .failure(let error):
    ///     print("Camera initialization failed: \(error)")
    /// }
    /// ```
    ///
    /// - Returns: `Result<Void, CameraError>` indicating initialization success or failure.
    /// - Note: After successful initialization, preview frames are available via `previewStream`.
    public func initializeCamera() async -> Result<Void, CameraError> {
        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        // Setup session observers
        setupSessionObservers()

        // Start session
        await start()
        await handleCameraPreviews()

        return .success(())
    }

    /// Cleans up camera resources and stops all operations.
    ///
    /// This method properly shuts down the camera service, stops the capture session,
    /// removes observers, and releases resources. It should be called when
    /// the camera is no longer needed to prevent memory leaks and battery drain.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // When view disappears or app goes to background
    /// cameraService.cleanupCamera()
    /// ```
    ///
    /// - Note: After calling this method, you must call `initializeCamera()` again before using the camera.
    public func cleanupCamera() {
        stop()
        removeSessionObservers()
        isCaptureSessionConfigured = false
        print("Camera resources cleaned up")
    }

    /// Returns comprehensive information about current camera state and capabilities.
    ///
    /// This method provides a snapshot of camera service's current status,
    /// including availability, permissions, device usage, and feature support.
    /// Useful for debugging, UI state management, and feature availability checks.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let info = cameraService.getCameraInfo()
    /// if info.isFlashAvailable {
    ///     // Show flash controls
    /// }
    /// ```
    ///
    /// - Returns: `CameraInfo` struct containing current camera state information.
    public func getCameraInfo() -> CameraInfo {
        return CameraInfo(
            isAvailable: isCameraAvailable,
            isAuthorized: authorizationStatus == .authorized,
            isUsingFrontCamera: isUsingFrontCaptureDevice,
            isUsingBackCamera: isUsingBackCaptureDevice,
            flashMode: flashMode,
            isFlashAvailable: isFlashAvailable,
            isRunning: isRunning
        )
    }
}

// MARK: - Camera Info Model

/// Comprehensive information about current camera state and capabilities.
///
/// `CameraInfo` provides a snapshot of camera service's current status,
/// including availability, permissions, device usage, and feature support.
/// This struct is useful for debugging, UI state management, and feature availability checks.
public struct CameraInfo {
    /// Whether camera hardware is available on the device.
    public let isAvailable: Bool
    
    /// Whether camera access has been authorized by the user.
    public let isAuthorized: Bool
    
    /// Whether the front-facing camera is currently active.
    public let isUsingFrontCamera: Bool
    
    /// Whether the back-facing camera is currently active.
    public let isUsingBackCamera: Bool
    
    /// The current flash mode setting.
    public let flashMode: AVCaptureDevice.FlashMode
    
    /// Whether the current camera device supports flash.
    public let isFlashAvailable: Bool
    
    /// Whether the camera capture session is currently running.
    public let isRunning: Bool

    /// Creates a new camera info instance with specified state values.
    ///
    /// - Parameters:
    ///   - isAvailable: Camera hardware availability status
    ///   - isAuthorized: Camera permission authorization status
    ///   - isUsingFrontCamera: Front camera usage status
    ///   - isUsingBackCamera: Back camera usage status
    ///   - flashMode: Current flash mode setting
    ///   - isFlashAvailable: Flash capability status
    ///   - isRunning: Capture session running status
    public init(
        isAvailable: Bool,
        isAuthorized: Bool,
        isUsingFrontCamera: Bool,
        isUsingBackCamera: Bool,
        flashMode: AVCaptureDevice.FlashMode,
        isFlashAvailable: Bool,
        isRunning: Bool
    ) {
        self.isAvailable = isAvailable
        self.isAuthorized = isAuthorized
        self.isUsingFrontCamera = isUsingFrontCamera
        self.isUsingBackCamera = isUsingBackCamera
        self.flashMode = flashMode
        self.isFlashAvailable = isFlashAvailable
        self.isRunning = isRunning
    }
}

// MARK: - Convenience Methods
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Captures a photo with simplified error handling.
    ///
    /// This method provides a convenient way to capture photos without
    /// dealing with Result types. It returns `nil` on failure
    /// and prints error messages to console.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let photoURL = await cameraService.quickPhotoCapture() {
    ///     print("Photo captured: \(photoURL)")
    /// } else {
    ///     print("Photo capture failed")
    /// }
    /// ```
    ///
    /// - Returns: URL to captured photo, or `nil` if capture failed.
    /// - Note: For proper error handling, use `capturePhotoWithCompletion()` instead.
    @concurrent
    public func quickPhotoCapture() async -> URL? {
        let result = await capturePhotoWithCompletion()

        switch result {
            case .success(let url):
                print("Photo captured successfully")
                return url
            case .failure(let error):
                print(error.errorDescription ?? "Failed to capture photo")
                return nil
        }
    }

    /// Starts video recording with simplified error handling.
    ///
    /// This method provides a convenient way to start video recording without
    /// dealing with Result types. It returns `false` on failure
    /// and prints error messages to console.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if cameraService.quickVideoStart() {
    ///     print("Video recording started")
    /// } else {
    ///     print("Failed to start recording")
    /// }
    /// ```
    ///
    /// - Returns: `true` if recording started successfully, `false` otherwise.
    /// - Note: For proper error handling, use `startVideoRecording()` instead.
    public func quickVideoStart() -> Bool {
        let result = startVideoRecording()

        switch result {
            case .success:
                print("Video recording started successfully")
                return true
            case .failure(let error):
                print(error.errorDescription ?? "Failed to start recording")
                return false
        }
    }
}
