//
//  CameraService+Intents.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

// MARK: - Camera Error

public enum CameraError: LocalizedError, Equatable {
    case permissionDenied
    case deviceNotAvailable
    case captureFailed
    case recordingFailed
    case configurationFailed
    case userCancelled
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

    /// Capture photo with completion handler
    @concurrent
    public func capturePhotoWithCompletion() async -> Result<URL, CameraError> {
        // Check permissions first
        let authorized = await checkAuthorization()
        guard authorized else {
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

        // Capture photo
        isLoading = true
        defer { isLoading = false }

        guard let photoURL = await capturePhoto() else {
            return .failure(.captureFailed)
        }

        return .success(photoURL)
    }

    /// Start video recording with completion handler
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

    /// Stop video recording and return URL
    @concurrent
    public func stopVideoRecording() async -> Result<URL, CameraError> {
        // This will be called when recording delegate finishes
        // For now, we'll return a placeholder result
        // The actual URL will come through the movieFileStream
        return .success(URL(fileURLWithPath: "placeholder"))
    }

    /// Initialize camera for use

    public func initializeCamera() async -> Result<Void, CameraError> {
        // Check permissions
        let authorized = await checkAuthorization()
        guard authorized else {
            return .failure(.permissionDenied)
        }

        // Check availability
        let available = await checkCameraAvailability()
        guard available else {
            return .failure(.deviceNotAvailable)
        }

        // Setup session observers
        setupSessionObservers()

        // Start session
        await start()
        await handleCameraPreviews()

        return .success(())
    }

    /// Cleanup camera resources
    public func cleanupCamera() {
        stop()
        removeSessionObservers()
        isCaptureSessionConfigured = false
        print("Camera resources cleaned up")
    }

    /// Get camera information
    public func getCameraInfo() -> CameraInfo {
        return CameraInfo(
            isAvailable: isCameraAvailable,
            isAuthorized: authorizationStatus == .authorized,
            isUsingFrontCamera: isUsingFrontCaptureDevice,
            isUsingBackCamera: isUsingBackCaptureDevice,
            flashMode: currentFlashMode,
            isRunning: isRunning
        )
    }
}

// MARK: - Camera Info Model

public struct CameraInfo {
    public let isAvailable: Bool
    public let isAuthorized: Bool
    public let isUsingFrontCamera: Bool
    public let isUsingBackCamera: Bool
    public let flashMode: AVCaptureDevice.FlashMode
    public let isRunning: Bool

    public init(
        isAvailable: Bool,
        isAuthorized: Bool,
        isUsingFrontCamera: Bool,
        isUsingBackCamera: Bool,
        flashMode: AVCaptureDevice.FlashMode,
        isRunning: Bool
    ) {
        self.isAvailable = isAvailable
        self.isAuthorized = isAuthorized
        self.isUsingFrontCamera = isUsingFrontCamera
        self.isUsingBackCamera = isUsingBackCamera
        self.flashMode = flashMode
        self.isRunning = isRunning
    }
}

// MARK: - Convenience Methods
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Quick photo capture with automatic error handling
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

    /// Quick video recording start with automatic error handling
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
