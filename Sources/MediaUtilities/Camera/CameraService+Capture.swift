//
//  CameraService+Capture.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

#if os(iOS)
import AudioToolbox
#endif

// MARK: - Capture Operations

@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Starts the camera capture session and begins streaming preview frames.
    ///
    /// This method configures the capture session if not already configured,
    /// checks for camera permissions, and starts the session.
    /// Preview frames will begin flowing through the `previewStream` after this call.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// await cameraService.start()
    /// // Preview frames are now available via previewStream
    /// ```
    ///
    /// - Note: This method is a no-op if the session is already running.
    public func start() async {
        guard authorizationStatus == .authorized else {
            return
        }

        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                sessionQueue.async { [self] in
                    self.captureSession.startRunning()
                }
            }
            return
        }

        sessionQueue.async { [self] in
            self.configureCaptureSession { success in
                guard success else {
                    return
                }
                self.captureSession.startRunning()
            }
        }
    }

    /// Stops the camera capture session and halts preview frame streaming.
    ///
    /// This method stops the capture session, which stops all camera operations
    /// including preview streaming, photo capture, and video recording.
    /// The session can be restarted by calling `start()` again.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// cameraService.stop()
    /// // Preview frames stop flowing through previewStream
    /// ```
    ///
    /// - Note: This method is a no-op if the session is not running.
    public func stop() {
        guard isCaptureSessionConfigured else {
            return
        }

        if captureSession.isRunning {
            sessionQueue.async { [self] in
                self.captureSession.stopRunning()
            }
        }
    }

    /// Switches between available front and back cameras.
    ///
    /// This method toggles between the front and back cameras if both are available.
    /// If only one camera is available, it switches to that camera.
    /// The capture session is automatically reconfigured for the new device.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// cameraService.switchCamera()
    /// // Camera switches from front to back or vice versa
    /// ```
    ///
    /// - Note: This method updates `isUsingFrontCaptureDevice` and `isUsingBackCaptureDevice` properties.
    public func switchCamera() {
        if let captureDevice = captureDevice, let index = availableCaptureDevices.firstIndex(of: captureDevice) {
            let nextIndex = (index + 1) % availableCaptureDevices.count
            self.captureDevice = availableCaptureDevices[nextIndex]
        } else {
            self.captureDevice = AVCaptureDevice.default(for: .video)
        }
    }

    /// Captures a photo using current camera settings and returns file URL.
    ///
    /// This method performs a low-level photo capture operation using the current
    /// camera configuration including flash mode, focus, and exposure settings.
    /// The captured photo is saved to a temporary file and the URL is returned.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// if let photoURL = await cameraService.capturePhoto() {
    ///     print("Photo saved to: \(photoURL)")
    /// }
    /// ```
    ///
    /// - Returns: URL to the captured photo file, or `nil` if capture failed.
    /// - Note: For user-friendly error handling, use `capturePhotoWithCompletion()` instead.
    @concurrent
    public func capturePhoto() async -> URL? {
        guard let photoOutput = self.photoOutput else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                var photoSettings = AVCapturePhotoSettings()

                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                }

                if #available(macOS 13.0, *) {
                    photoSettings.flashMode = flashMode
                    #if os(iOS)
                    if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                        photoSettings.previewPhotoFormat = [
                            kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType
                        ]
                    }
                    #endif  // os(iOS)

                    photoSettings.photoQualityPrioritization = .balanced

                    if let photoOutputVideoConnection = photoOutput.connection(with: .video) {
                        if #available(iOS 17.0, macOS 14.0, *) {
                            photoOutputVideoConnection.videoRotationAngle = RotationAngle.portrait.rawValue
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                }

                // Store continuation to be called in delegate
                self.photoCaptureContinuation = continuation

                photoOutput.capturePhoto(with: photoSettings, delegate: self)
            }
        }
    }

    /// Starts recording video to a temporary file.
    ///
    /// This method begins video recording using the current camera configuration.
    /// The video is saved to a temporary file in the documents directory.
    /// Recording continues until `stopRecordingVideo()` is called.
    /// Torch mode is automatically configured based on flash settings.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// cameraService.startRecordingVideo()
    /// // Video recording starts...
    /// cameraService.stopRecordingVideo()
    /// ```
    ///
    /// - Note: Use `movieFileStream` to receive the URL when recording completes.
    public func startRecordingVideo() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }

        guard
            let directoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return
        }

        // Torch is already configured by toggleFlashMode() for immediate feedback
        // No need to configure it again here

        let fileName = UUID().uuidString
        let filePath = directoryPath.appendingPathComponent(fileName).appendingPathExtension("mp4")
        movieFileOutput.startRecording(to: filePath, recordingDelegate: self)

        // Play system sound for recording start
        playRecordingStartSound()
    }

    /// Stops video recording and finalizes the output file.
    ///
    /// This method stops the current video recording session and finalizes
    /// the output file. The completed video URL will be delivered
    /// through the `movieFileStream` async stream.
    /// Torch state is preserved after recording stops.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// cameraService.startRecordingVideo()
    /// // Recording in progress...
    /// cameraService.stopRecordingVideo()
    /// // URL will be available via movieFileStream
    /// ```
    ///
    /// - Note: This method is a no-op if no recording is in progress.
    public func stopRecordingVideo() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }

        // Torch state is preserved - don't turn it off automatically
        // User can turn it off manually via flash button if desired

        movieFileOutput.stopRecording()

        // Play system sound for recording stop
        playRecordingStopSound()
    }

    /// Toggles through available flash modes for the current camera.
    ///
    /// This method cycles through flash modes in the order: off → on → auto → off.
    /// The method updates the published `flashMode` property.
    /// For photos: flash activates only during photo capture.
    /// For videos: torch activates immediately when enabled (like iPhone Camera app).
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let success = cameraService.toggleFlashMode()
    /// if success {
    ///     print("Flash mode changed to: \(cameraService.flashMode)")
    /// }
    /// ```
    ///
    /// - Returns: `true` if flash mode was successfully changed, `false` if flash is not available.
    /// - Note: Flash is only available on iOS devices that support it.
    public func toggleFlashMode() {
        guard isFlashAvailable else {
            return
        }

        // Update the appropriate mode based on current capture mode
        if captureMode == .photo {
            if photoFlashMode == .off {
                photoFlashMode = .on
            } else if photoFlashMode == .on {
                photoFlashMode = .auto
            } else {
                photoFlashMode = .off
            }
        } else {
            if videoTorchMode == .off {
                videoTorchMode = .on
            } else if videoTorchMode == .on {
                videoTorchMode = .auto
            } else {
                videoTorchMode = .off
            }

            // For video mode, activate/deactivate torch immediately (like iPhone Camera app)
            updateTorchForVideoMode()
        }
    }

    /// Plays the system default sound for video recording start.
    ///
    /// This provides audio feedback when video recording begins,
    /// following standard iOS camera app UX patterns.
    private func playRecordingStartSound() {
        #if os(iOS)
        // Use system sound for recording start (usually a short beep)
        AudioServicesPlaySystemSound(1113)  // Standard iOS camera recording start sound
        #endif
    }

    /// Plays the system default sound for video recording end.
    ///
    /// This provides audio feedback when video recording stops,
    /// following standard iOS camera app UX patterns.
    private func playRecordingStopSound() {
        #if os(iOS)
        // Use system sound for recording stop (usually a different tone)
        AudioServicesPlaySystemSound(1114)  // Standard iOS camera recording stop sound
        #endif
    }

    /// Updates torch state based on current capture mode and settings.
    ///
    /// This method ensures the torch state matches the current mode's settings.
    /// For photo mode: torch is off
    /// For video mode: torch matches videoTorchMode setting
    func updateTorchForCurrentMode() {
        guard let captureDevice = captureDevice, isTorchAvailable else {
            return
        }

        do {
            try captureDevice.lockForConfiguration()
            defer { captureDevice.unlockForConfiguration() }

            if captureMode == .photo {
                // In photo mode, ensure torch is off
                if captureDevice.torchMode != .off {
                    captureDevice.torchMode = .off
                }
            } else {
                // In video mode, set torch according to videoTorchMode
                switch videoTorchMode {
                    case .off:
                        if captureDevice.torchMode != .off {
                            captureDevice.torchMode = .off
                        }
                    case .on:
                        captureDevice.torchMode = .on
                    case .auto:
                        captureDevice.torchMode = .auto
                    @unknown default:
                        captureDevice.torchMode = .off
                }
            }
        } catch {
            // Torch update failed - continue silently
        }
    }

    /// Updates torch state immediately for video mode (like iPhone Camera app).
    ///
    /// When in video mode, torch should turn on/off immediately when flash button is pressed,
    /// providing instant visual feedback to the user.
    private func updateTorchForVideoMode() {
        guard captureMode == .video, let captureDevice = captureDevice, isTorchAvailable else {
            return
        }

        do {
            try captureDevice.lockForConfiguration()
            defer { captureDevice.unlockForConfiguration() }

            switch videoTorchMode {
                case .off:
                    if captureDevice.torchMode != .off {
                        captureDevice.torchMode = .off
                    }
                case .on:
                    captureDevice.torchMode = .on
                case .auto:
                    captureDevice.torchMode = .auto
                @unknown default:
                    captureDevice.torchMode = .off
            }
        } catch {
            // Torch update failed - continue silently
        }
    }

    /// Configures torch mode for video recording based on current flash settings.
    ///
    /// This method activates torch during video recording if flash is enabled.
    /// Torch is only active during actual recording, not just when flash button is pressed.
    private func configureTorchForVideoRecording() {
        guard let captureDevice = captureDevice, isTorchAvailable else {
            return
        }

        do {
            try captureDevice.lockForConfiguration()
            defer { captureDevice.unlockForConfiguration() }

            switch flashMode {
                case .off:
                    // Torch remains off
                    break
                case .on:
                    captureDevice.torchMode = .on
                case .auto:
                    captureDevice.torchMode = .auto
                @unknown default:
                    break
            }
        } catch {
            // Torch configuration failed - continue silently
        }
    }
}

// MARK: - Private Properties for Capture
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {
    /// Associated object storage for photo capture continuation.
    ///
    /// This property bridges Swift concurrency with AVFoundation's delegate-based API.
    /// When `capturePhoto()` is called, it creates a `CheckedContinuation` that needs to be
    /// resumed later when the delegate method `photoOutput(_:didFinishProcessingPhoto:error:)`
    /// is called. Since `CameraService` is a final class and we can't add stored properties,
    /// we use Objective-C associated objects to store the continuation temporarily.
    ///
    /// The continuation is set in `capturePhoto()` and resumed in the delegate methods.
    /// It's automatically cleaned up after use and during `cleanupCamera()`.
    ///
    /// This pattern is necessary because:
    /// - AVFoundation uses asynchronous delegates, not completion handlers
    /// - Swift concurrency requires bridging to resume async operations
    /// - Associated objects provide thread-safe storage without modifying the class
    ///
    /// Thread Safety: Associated objects are thread-safe and handle the sessionQueue context properly.
    ///
    /// - Note: I am not entirely confident of this approach and if you have a better implementation you are encouraged to send a PR
    var photoCaptureContinuation: CheckedContinuation<URL?, Never>? {
        get {
            objc_getAssociatedObject(self, &photoCaptureContinuationKey) as? CheckedContinuation<URL?, Never>
        }
        set {
            objc_setAssociatedObject(self, &photoCaptureContinuationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// Associated object keys
private var photoCaptureContinuationKey: UInt8 = 0
