//
//  CameraService+Capture.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

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
            print("Camera access not authorized, cannot start session")
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
                    print("Failed to configure capture session")
                    return
                }
                self.captureSession.startRunning()
                print("Capture session started successfully")
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
            print("Capture session not configured, cannot stop")
            return
        }

        if captureSession.isRunning {
            sessionQueue.async { [self] in
                self.captureSession.stopRunning()
                print("Capture session stopped")
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
            print("Switched to camera at index \(nextIndex)")
        } else {
            self.captureDevice = AVCaptureDevice.default(for: .video)
            print("Switched to default camera")
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
            print("Photo output not available")
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
                print("Photo capture initiated")
            }
        }
    }

    /// Starts recording video to a temporary file.
    ///
    /// This method begins video recording using the current camera configuration.
    /// The video is saved to a temporary file in the documents directory.
    /// Recording continues until `stopRecordingVideo()` is called.
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
            print("Cannot find movie file output")
            print("Video recording not available")
            return
        }

        guard
            let directoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            print("Cannot access local file domain")
            print("Cannot save video to device")
            return
        }

        let fileName = UUID().uuidString
        let filePath = directoryPath.appendingPathComponent(fileName).appendingPathExtension("mp4")

        movieFileOutput.startRecording(to: filePath, recordingDelegate: self)
        print("Video recording started to: \(filePath.path)")
    }

    /// Stops video recording and finalizes the output file.
    ///
    /// This method stops the current video recording session and finalizes
    /// the output file. The completed video URL will be delivered
    /// through the `movieFileStream` async stream.
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
            print("Cannot find movie file output")
            return
        }
        movieFileOutput.stopRecording()
        print("Video recording stopped")
    }

    /// Toggles through available flash modes for the current camera.
    ///
    /// This method cycles through flash modes in the order: off → on → auto → off.
    /// The method updates both the device flash mode and the published `flashMode` property.
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
    public func toggleFlashMode() -> Bool {
        guard isFlashAvailable else {
            print("Flash not available on current device")
            return false
        }

        if flashMode == .off {
            flashMode = .on
            print("Flash turned on")
        } else if flashMode == .on {
            flashMode = .auto
            print("Flash set to auto")
        } else {
            flashMode = .off
            print("Flash turned off")
        }
        return true

    }
}

// MARK: - Private Properties for Capture
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {
    // Store continuation for photo capture
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
