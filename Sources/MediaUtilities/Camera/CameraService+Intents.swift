//
//  CameraService+Intents.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import CoreImage
import Foundation

// MARK: - Camera Error

/// Errors that can occur during camera operations.
///
/// The `CameraError` enum encompasses all possible failure scenarios
/// when working with the camera service, providing localized descriptions
/// for user-facing error messages and enabling proper error handling.
///
/// ## Usage
///
/// ```swift
/// let result = await cameraService.capturePhoto()
/// switch result {
/// case .success(let url):
///     print("Photo saved to: \(url)")
/// case .failure(let error):
///     print(error.localizedDescription)
/// }
/// ```
public enum CameraError: LocalizedError, Equatable {
    /// Camera access was denied by the user.
    case permissionDenied

    /// Microphone access was denied by the user.
    case microphonePermissionDenied

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
            case .microphonePermissionDenied:
                return "Microphone access denied. Please enable in Settings"
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

    /// Captures a still photo with full error handling.
    ///
    /// Starts the session if it is not already running, then captures a photo
    /// and saves it to a temporary file. The `isCapturingPhoto` published
    /// property is `true` for the duration of the capture.
    ///
    /// - Returns: `.success` with the photo file URL, or a `.failure`
    ///   describing why the capture could not be performed.
    public func capturePhoto() async -> Result<URL, CameraError> {
        guard authorizationStatus == .authorized else {
            return .failure(.permissionDenied)
        }

        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        if !isRunning {
            guard await start() else {
                return .failure(.configurationFailed)
            }
        }

        isCapturingPhoto = true

        let photoURL = await engine.capturePhoto(flashMode: flashMode)
        isCapturingPhoto = false

        guard let photoURL else {
            return .failure(.captureFailed)
        }
        return .success(photoURL)
    }

    /// Starts video recording with full error handling.
    ///
    /// Requests microphone access when it has not been determined yet, starts
    /// the session if necessary, and begins recording to a temporary file.
    /// The recording continues until `stopVideoRecording()` is called.
    ///
    /// - Returns: `.success` when recording begins, or a `.failure`
    ///   describing why recording could not be started.
    public func startVideoRecording() async -> Result<Void, CameraError> {
        guard authorizationStatus == .authorized else {
            return .failure(.permissionDenied)
        }

        // Lazily request audio permission if not yet determined
        if microphoneAuthorizationStatus == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .audio)
        }

        guard microphoneAuthorizationStatus == .authorized else {
            return .failure(.microphonePermissionDenied)
        }

        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        if !isRunning {
            guard await start() else {
                return .failure(.configurationFailed)
            }
        }

        return await startRecordingVideo()
    }

    /// Stops the in-progress video recording.
    ///
    /// - Returns: `.success` with the completed file URL, or a `.failure`
    ///   describing why the recording could not be finalized.
    public func stopVideoRecording() async -> Result<URL, CameraError> {
        await stopRecordingVideo()
    }

    /// Initializes the camera service for use.
    ///
    /// Performs the complete initialization sequence: permission checking and
    /// requesting, notification observation, capture file hygiene, device
    /// discovery, session configuration, lens state publication, and preview
    /// stream setup.
    ///
    /// - Returns: `.success` once the session is running and the preview
    ///   pipeline is active, or a `.failure` describing why initialization
    ///   could not complete.
    ///
    /// - Note: Call `cleanupCamera()` when the camera UI disappears; call
    ///   this method again to re-initialize afterwards.
    public func initializeCamera() async -> Result<Void, CameraError> {
        // Clear any previous session error
        sessionError = nil

        if authorizationStatus == .notDetermined {
            await requestCameraAccess()
        }
        if authorizationStatus != .authorized {
            return .failure(.permissionDenied)
        }
        guard isCameraAvailable else {
            return .failure(.deviceNotAvailable)
        }

        // Start observing runtime notifications via the engine.
        await engine.startObservingNotifications()

        // Purge capture files left behind by previous sessions (older than
        // 24 hours). Runs off the main actor; consumers are expected to have
        // consumed URLs they were given long before then.
        purgeStaleCaptureFiles()

        // Start session and wait for it to be running
        guard await start() else {
            return .failure(.configurationFailed)
        }

        // The active device is now known — publish its lens state.
        lensCount = engine.lensCountSnapshot()
        lensMagnifications = engine.lensMagnificationsSnapshot()
        selectedLensIndex = engine.selectedLensIndexSnapshot()

        // Run preview loop detached so initializeCamera() can return
        Task { await handleCameraPreviews() }

        return .success(())
    }

    /// Cleans up camera resources and stops all operations.
    ///
    /// Cancels the preview loop and notification observers, stops the capture
    /// session, and resets all published state to its defaults.
    ///
    /// - Note: After calling this method, you must call `initializeCamera()`
    ///   again before using the camera.
    public func cleanupCamera() async {
        await engine.cleanup()

        // Reset facade state
        isCapturingPhoto = false
        isPreviewPaused = false
        isSessionInterrupted = false
        isSwitchingCaptureMode = false
        sessionError = nil
        previewImage = nil
        previewAspectRatio = nil
        lensCount = 1
        lensMagnifications = []
        selectedLensIndex = 0

        // Reset mode and flash/torch to defaults
        photoFlashMode = .off
        videoTorchMode = .off
        // Photo is the preferred default mode whenever it is allowed.
        captureMode =
            allowedCaptureModes.contains(.photo)
            ? .photo
            : (allowedCaptureModes.first ?? .photo)

        // Cancel preview loop
        previewLoop?.cancel()
        previewLoop = nil

        // Recreate the preview stream for potential re-initialization
        var previewContinuation: AsyncStream<CIImage>.Continuation!
        previewStream = AsyncStream<CIImage>(bufferingPolicy: .bufferingNewest(1)) { previewContinuation = $0 }
        // Push the new continuation into the engine so future starts use it.
        Task { [engine] in
            await engine.replacePreviewContinuation(previewContinuation)
        }
    }

    /// Returns comprehensive information about the current camera state.
    ///
    /// - Returns: A `CameraInfo` snapshot of availability, authorization,
    ///   active camera position, flash state, and session status.
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

/// Comprehensive information about the current camera state and capabilities.
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
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

// MARK: - Capture File Hygiene

@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Deletes capture files older than 24 hours from the temporary
    /// directory. The system purges tmp under storage pressure as well; this
    /// bounds growth within an app's lifetime. Runs off the main actor.
    fileprivate func purgeStaleCaptureFiles() {
        Task.detached(priority: .utility) {
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: temporaryDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []

            for file in files where file.lastPathComponent.hasPrefix("camera_photo_") {
                let modified =
                    (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
