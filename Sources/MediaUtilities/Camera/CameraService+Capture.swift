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

    /// Start the camera session (from provided code)

    public func start() async {
        let authorized = await checkAuthorization()
        guard authorized else {
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

    /// Stop the camera session (from provided code)
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

    /// Switch between available cameras (from provided code)
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

    /// Take a photo (adapted from provided code)
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

                let isFlashAvailable = self.deviceInput?.device.isFlashAvailable ?? false

                if #available(iOS 13.0, macOS 13.0, *) {
                    photoSettings.flashMode = isFlashAvailable ? .auto : .off
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

    /// Start recording video (from provided code)
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
        let filePath =
            directoryPath
            .appendingPathComponent(fileName)
            .appendingPathExtension("mp4")

        movieFileOutput.startRecording(to: filePath, recordingDelegate: self)
        print("Video recording started to: \(filePath.path)")
    }

    /// Stop recording video (from provided code)
    public func stopRecordingVideo() {
        guard let movieFileOutput = self.movieFileOutput else {
            print("Cannot find movie file output")
            return
        }
        movieFileOutput.stopRecording()
        print("Video recording stopped")
    }

    /// Toggle flash mode
    public func toggleFlashMode() -> Bool {
        guard let device = captureDevice, device.isFlashAvailable else {
            print("Flash not available on current device")
            return false
        }

        do {
            try device.lockForConfiguration()

            if device.flashMode == .off {
                device.flashMode = .on
                print("Flash turned on")
            } else if device.flashMode == .on {
                device.flashMode = .auto
                print("Flash set to auto")
            } else {
                device.flashMode = .off
                print("Flash turned off")
            }
            device.unlockForConfiguration()
            return true
        } catch {
            print("Error toggling flash: \(error.localizedDescription)")
            return false
        }
    }

    /// Get current flash mode
    public var currentFlashMode: AVCaptureDevice.FlashMode {
        guard let device = captureDevice, device.isFlashAvailable else {
            return .off
        }
        return device.flashMode
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
