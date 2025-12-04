//
//  CameraService.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import CoreImage
import Foundation
import SwiftUI

/// A comprehensive camera management service that provides unified access to device cameras
/// across iOS and macOS platforms with modern Swift concurrency support.
///
/// The `CameraService` handles all camera operations including:
/// - Device discovery and configuration management
/// - Live preview streaming with async/await patterns
/// - Photo and video capture with proper error handling
/// - Flash mode control and camera switching
/// - Permission management and status tracking
/// - Thread-safe operations using dedicated dispatch queues
///
/// ## Architecture
///
/// The service uses a modular architecture with separate extensions for different concerns:
/// - **Capture Operations**: Photo/video recording and session management
/// - **Delegate Handling**: AVFoundation delegate implementations
/// - **High-Level Intents**: User-friendly async APIs with Result types
/// - **Permission Management**: Camera access request handling
///
/// ## Usage
///
/// ```swift
/// let cameraService = CameraService()
/// await cameraService.initializeCamera()
///
/// let result = await cameraService.capturePhotoWithCompletion()
/// switch result {
/// case .success(let url):
///     print("Photo saved to: \(url)")
/// case .failure(let error):
///     print("Capture failed: \(error)")
/// }
///
/// // Monitor live preview
/// for await ciImage in cameraService.previewStream {
///     // Process preview frames
/// }
/// ```
///
/// ## Thread Safety
///
/// All camera operations are performed on a dedicated `sessionQueue` to ensure thread safety.
/// UI updates should be performed on the main thread using `@MainActor` or `DispatchQueue.main`.
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
/// - Some features (like flash) are iOS-only
///
@available(iOS 13.0, macOS 10.15, *)
public final class CameraService: NSObject, ObservableObject, Sendable {

    // MARK: - Core Properties

    @Published var previewImage: Image?
    let captureSession = AVCaptureSession()
    var isCaptureSessionConfigured = false
    var deviceInput: AVCaptureDeviceInput?
    var photoOutput: AVCapturePhotoOutput?
    var movieFileOutput: AVCaptureMovieFileOutput?
    var videoOutput: AVCaptureVideoDataOutput?
    var sessionQueue: DispatchQueue!

    // MARK: - Public Observable Properties

    /// The current flash mode setting for the camera.
    ///
    /// This property controls the flash behavior when capturing photos.
    /// Changes to this property are automatically reflected in the UI.
    /// - Note: Flash is only available on iOS devices that support it.
    @Published public var flashMode: AVCaptureDevice.FlashMode = .off

    /// Indicates whether a photo capture operation is currently in progress.
    ///
    /// This property is automatically updated during photo capture operations
    /// and can be used to show loading states or prevent multiple simultaneous captures.
    @Published public var isCapturingPhoto: Bool = false

    /// Controls whether the camera preview is currently paused.
    ///
    /// When set to `true`, the preview stream stops delivering new frames
    /// but the capture session remains active. This can be useful for
    /// performance optimization or when the camera view is not visible.
    @Published public var isPreviewPaused = false

    // MARK: - Device Properties

    private var allCaptureDevices: [AVCaptureDevice] {
        #if os(iOS)
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTrueDepthCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera,
                .builtInDualWideCamera,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
        #elseif os(macOS)
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
        #endif
    }

    private var frontCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices.filter { $0.position == .front }
    }

    private var backCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices.filter { $0.position == .back }
    }

    private var captureDevices: [AVCaptureDevice] {
        var devices = [AVCaptureDevice]()
        if let backDevice = backCaptureDevices.first {
            devices += [backDevice]
        }
        if let frontDevice = frontCaptureDevices.first {
            devices += [frontDevice]
        }
        return devices
    }

    var availableCaptureDevices: [AVCaptureDevice] {
        if #available(iOS 14.0, *) {
            captureDevices
                .filter { $0.isConnected }
                .filter { !$0.isSuspended }
        } else {
            captureDevices
                .filter { $0.isConnected }
        }
    }

    var captureDevice: AVCaptureDevice? {
        didSet {
            guard let captureDevice = captureDevice else { return }
            sessionQueue.async {
                self.updateSessionForCaptureDevice(captureDevice)
            }
        }
    }

    // MARK: - Public Computed Properties

    /// A Boolean value indicating whether the camera capture session is currently running.
    ///
    /// When `true`, the camera is actively capturing and providing preview frames.
    /// When `false`, the session is stopped and no camera operations are active.
    public var isRunning: Bool {
        captureSession.isRunning
    }

    /// A Boolean value indicating whether the front-facing camera is currently active.
    ///
    /// Returns `true` if the current capture device is positioned on the front of the device,
    /// suitable for selfies and video calls. Returns `false` if back camera is active
    /// or no camera is selected.
    public var isUsingFrontCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return frontCaptureDevices.contains(captureDevice)
    }

    /// A Boolean value indicating whether the back-facing camera is currently active.
    ///
    /// Returns `true` if the current capture device is positioned on the back of the device,
    /// typically used for standard photography and video recording. Returns `false`
    /// if front camera is active or no camera is selected.
    public var isUsingBackCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return backCaptureDevices.contains(captureDevice)
    }

    /// A Boolean value indicating whether the current camera device supports flash.
    ///
    /// Returns `true` if the currently selected camera device has flash capabilities.
    /// Flash is typically available on back cameras but not on front cameras.
    /// This property updates automatically when switching between cameras.
    public var isFlashAvailable: Bool {
        guard let captureDevice = captureDevice else { return false }
        return captureDevice.isFlashAvailable
    }

    /// The current authorization status for camera access.
    ///
    /// This property returns the current permission status for camera access
    /// without triggering a permission request. Use `requestCameraAccess()`
    /// to prompt the user for permission if needed.
    public var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// A Boolean value indicating whether any camera devices are available on the current device.
    ///
    /// Returns `true` if the device has at least one available camera that can be used
    /// for capture operations. Returns `false` if no cameras are detected or all cameras
    /// are unavailable (disconnected or suspended).
    /// A Boolean value indicating whether any camera devices are available and authorized.
    ///
    /// Returns `true` if the device has at least one available camera that can be used
    /// for capture operations AND camera access has been authorized by the user.
    /// Returns `false` if no cameras are detected, all cameras are unavailable,
    /// or camera access has not been granted.
    public var isCameraAvailable: Bool {
        authorizationStatus == .authorized && !availableCaptureDevices.isEmpty
    }

    // MARK: - Async Streams

    var addToPhotoStream: ((AVCapturePhoto) -> Void)?

    /// An async stream that delivers captured photos as they become available.
    ///
    /// This stream provides `AVCapturePhoto` objects as they are captured by the camera.
    /// Use this stream for real-time photo processing or to build custom photo handling logic.
    /// The stream continues until the camera service is deallocated.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// for await photo in cameraService.photoStream {
    ///     // Process captured photo
    ///     print("Photo captured: \(photo)")
    /// }
    /// ```
    var photoStream: AsyncStream<AVCapturePhoto> {
        AsyncStream { continuation in
            addToPhotoStream = { photo in
                continuation.yield(photo)
            }
        }
    }

    var addToMovieFileStream: ((URL) -> Void)?

    /// An async stream that delivers URLs of completed video recordings.
    ///
    /// This stream provides local file URLs for videos as they finish recording.
    /// Each URL points to a video file stored in the device's documents directory.
    /// The stream continues until the camera service is deallocated.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// for await videoURL in cameraService.movieFileStream {
    ///     // Handle completed video recording
    ///     print("Video saved to: \(videoURL)")
    /// }
    /// ```
    public var movieFileStream: AsyncStream<URL> {
        AsyncStream { continuation in
            addToMovieFileStream = { fileUrl in
                continuation.yield(fileUrl)
            }
        }
    }

    var addToPreviewStream: ((CIImage) -> Void)?

    /// An async stream that delivers live camera preview frames.
    ///
    /// This stream provides `CIImage` objects representing the current camera preview
    /// at approximately 30 FPS. Frames are only delivered when `isPreviewPaused` is `false`.
    /// Use this stream for custom preview processing or computer vision tasks.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// for await ciImage in cameraService.previewStream {
    ///     // Process preview frame
    ///     let uiImage = UIImage(ciImage: ciImage)
    /// }
    /// ```
    ///
    /// - Note: Preview frames are delivered on a background queue. Update UI on main thread.
    public var previewStream: AsyncStream<CIImage> {
        AsyncStream { continuation in
            addToPreviewStream = { ciImage in
                if !self.isPreviewPaused {
                    continuation.yield(ciImage)
                }
            }
        }
    }

    func handleCameraPreviews() async {
        let imageStream = previewStream.map { $0.image }

        for await image in imageStream {
            Task { @MainActor in
                previewImage = image
            }
        }
    }

    // MARK: - Initialization

    public override init() {
        super.init()

        captureSession.sessionPreset = .photo
        sessionQueue = DispatchQueue(label: "session queue")
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
    }

    // MARK: - Private Helper Methods

    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let error {
            print("Error getting capture device input: \(error.localizedDescription)")
            return nil
        }
    }

    private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                captureSession.removeInput(deviceInput)
            }
        }

        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }

        updateVideoOutputConnection()
    }

    private func updateVideoOutputConnection() {
        if let videoOutput = videoOutput, let videoOutputConnection = videoOutput.connection(with: .video) {
            if videoOutputConnection.isVideoMirroringSupported {
                videoOutputConnection.isVideoMirrored = isUsingFrontCaptureDevice
            }
        }
    }

    func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {
        var success = false

        self.captureSession.beginConfiguration()

        defer {
            self.captureSession.commitConfiguration()
            completionHandler(success)
        }

        guard
            let captureDevice = captureDevice,
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            print("Failed to obtain video input.")
            return
        }

        let movieFileOutput = AVCaptureMovieFileOutput()
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))

        guard captureSession.canAddInput(deviceInput) else {
            print("Unable to add device input to capture session.")
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            print("Unable to add photo output to capture session.")
            return
        }
        guard captureSession.canAddOutput(videoOutput) else {
            print("Unable to add video output to capture session.")
            return
        }

        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        captureSession.addOutput(movieFileOutput)

        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.videoOutput = videoOutput
        self.movieFileOutput = movieFileOutput

        if #available(macOS 13.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .balanced
        } else {
            // Fallback on earlier versions
        }

        updateVideoOutputConnection()

        isCaptureSessionConfigured = true
        success = true

        print("Capture session configured successfully")
    }
}

// MARK: - Rotation Angle

enum RotationAngle: CGFloat {
    case portrait = 90
    case portraitUpsideDown = 270
    case landscapeRight = 180
    case landscapeLeft = 0
}

@available(iOS 13.0, macOS 10.15, *)
extension CIImage {
    fileprivate var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
