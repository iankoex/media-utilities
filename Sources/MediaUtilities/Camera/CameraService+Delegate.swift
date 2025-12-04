//
//  CameraService+Delegate.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import CoreImage
import Foundation

// MARK: - AVCapturePhotoCaptureDelegate

@available(iOS 13.0, macOS 10.15, *)
extension CameraService: AVCapturePhotoCaptureDelegate {

    public func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            print("Failed to capture photo")
            photoCaptureContinuation?.resume(returning: nil)
            return
        }

        // Process photo data and save to temporary file
        guard let imageData = photo.fileDataRepresentation() else {
            print("No image data representation available")
            print("Failed to process photo")
            photoCaptureContinuation?.resume(returning: nil)
            return
        }

        // Save to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera_photo_\(UUID().uuidString).jpg")

        do {
            try imageData.write(to: tempURL)
            print("Photo saved to: \(tempURL.path)")

            // Add to stream and resume continuation
            addToPhotoStream?(photo)
            photoCaptureContinuation?.resume(returning: tempURL)
        } catch {
            print("Error saving photo: \(error.localizedDescription)")
            print("Failed to save photo")
            photoCaptureContinuation?.resume(returning: nil)
        }
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("Photo capture will begin")
    }

    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didCapturePhotoForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("Photo capture completed")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
@available(iOS 13.0, macOS 10.15, *)
extension CameraService: AVCaptureFileOutputRecordingDelegate {

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error = error {
            print("Error recording video: \(error.localizedDescription)")
            print("Failed to record video")
            return
        }

        print("Video saved to: \(outputFileURL.path)")
        addToMovieFileStream?(outputFileURL)
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording started to: \(outputURL.path)")
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didPauseRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording paused")
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didResumeRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording resumed")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
@available(iOS 13.0, macOS 10.15, *)
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        // Set rotation angle for portrait orientation
        if #available(iOS 17.0, macOS 14.0, *) {
            connection.videoRotationAngle = RotationAngle.portrait.rawValue
        } else {
            // Fallback on earlier versions
        }

        // Create CIImage and add to preview stream
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        addToPreviewStream?(ciImage)
    }

    public func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        // print dropped frames for debugging
        print("Dropped video frame")
    }
}

// MARK: - AVCaptureSession Runtime Notifications
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Setup notification observers for session runtime
    public func setupSessionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: captureSession
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: captureSession
        )
    }

    /// Remove notification observers
    public func removeSessionObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        print("Capture session runtime error: \(notification)")
        #if os(iOS)
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            return
        }

        if error.code == .deviceNotConnected {
            print("Camera disconnected")
        } else if error.code == .mediaServicesWereReset {
            print("Media services were reset, restarting session")
            Task {
                await start()
            }
        }
        #endif
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        print("Capture session was interrupted")

        #if os(iOS)
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonValue)
        else {
            return
        }

        if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
            print("Camera is being used by another app")
        }
        #endif
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        print("Capture session interruption ended")

        // Restart session if needed
        if !captureSession.isRunning && isCaptureSessionConfigured {
            Task {
                await start()
            }
        }
    }
}
