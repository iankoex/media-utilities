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

    /// Called when photo capture processing is complete.
    ///
    /// This delegate method is called when the camera finishes processing a captured photo.
    /// It handles both successful captures and errors, resuming the async continuation
    /// with the appropriate result.
    ///
    /// - Parameters:
    ///   - output: The photo output that produced the capture
    ///   - photo: The captured photo object containing image data and metadata
    ///   - error: Error information if capture failed, or nil if successful
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

    /// Called immediately before photo capture begins.
    ///
    /// This delegate method is called when the camera is about to capture a photo
    /// after the user has triggered the capture. It can be used for UI updates
    /// or preparing for the upcoming capture.
    ///
    /// - Parameters:
    ///   - output: The photo output that will perform the capture
    ///   - resolvedSettings: The resolved settings that will be used for capture
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("Photo capture will begin")
    }

    /// Called when photo capture has been triggered.
    ///
    /// This delegate method is called when the camera has actually captured the photo
    /// but before processing is complete. It indicates that the capture was successful.
    ///
    /// - Parameters:
    ///   - output: The photo output that performed the capture
    ///   - resolvedSettings: The settings that were used for the capture
    public func photoOutput(
        _ output: AVCapturePhotoOutput, didCapturePhotoForResolvedSettings resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        print("Photo capture completed")
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
@available(iOS 13.0, macOS 10.15, *)
extension CameraService: AVCaptureFileOutputRecordingDelegate {

    /// Called when video recording finishes and file is ready.
    ///
    /// This delegate method is called when video recording completes and the output
    /// file has been finalized. It handles both successful recordings and errors,
    /// delivering the URL through the movie file stream.
    ///
    /// - Parameters:
    ///   - output: The file output that performed the recording
    ///   - outputFileURL: URL to the completed video file
    ///   - connections: The connections used for recording
    ///   - error: Error information if recording failed, or nil if successful
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

    /// Called when video recording starts.
    ///
    /// This delegate method is called when video recording begins and the output
    /// file has been created. It indicates that recording is actively in progress.
    ///
    /// - Parameters:
    ///   - output: The file output that started recording
    ///   - outputURL: URL to the video file being created
    ///   - connections: The connections used for recording
    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording started to: \(outputURL.path)")
    }

    /// Called when video recording is about to resume.
    ///
    /// This delegate method is called when a paused video recording
    /// is about to resume. It provides advance notice before recording continues.
    ///
    /// - Parameters:
    ///   - output: The file output that will resume recording
    ///   - outputURL: URL to the video file being resumed
    ///   - connections: The connections used for recording
    public func fileOutput(
        _ output: AVCaptureFileOutput,
        willResumeRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording will resume to: \(outputURL.path)")
    }

    /// Called when video recording is paused.
    ///
    /// This delegate method is called when video recording is paused.
    /// The recording can be resumed later using the resume functionality.
    ///
    /// - Parameters:
    ///   - output: The file output that paused recording
    ///   - outputURL: URL to the video file that was paused
    ///   - connections: The connections used for recording
    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didPauseRecordingTo outputURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        print("Video recording paused")
    }

    /// Called when video recording resumes after being paused.
    ///
    /// This delegate method is called when a paused video recording
    /// resumes and continues capturing to the same file.
    ///
    /// - Parameters:
    ///   - output: The file output that resumed recording
    ///   - outputURL: URL to the video file that resumed
    ///   - connections: The connections used for recording
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

    /// Called when a new video frame is available from the camera.
    ///
    /// This delegate method provides real-time video frames from the camera
    /// that can be used for preview display or computer vision processing.
    /// Frames are delivered at approximately 30 FPS.
    ///
    /// - Parameters:
    ///   - output: The output that produced the frame
    ///   - sampleBuffer: The video frame data buffer
    ///   - connection: The connection used for the output
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

    /// Called when video frames are dropped during processing.
    ///
    /// This delegate method is called when the system drops video frames
    /// due to performance constraints or processing bottlenecks.
    /// It can be used for performance monitoring and debugging.
    ///
    /// - Parameters:
    ///   - output: The output that dropped frames
    ///   - sampleBuffer: The dropped frame buffer
    ///   - connection: The connection used for the output
    public func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        print("Dropped video frame")
    }
}

// MARK: - AVCaptureSession Runtime Notifications
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Sets up notification observers for capture session runtime events.
    ///
    /// This method configures observers for session runtime errors and interruptions,
    /// allowing the service to handle unexpected camera disconnections or
    /// system interruptions (like phone calls or other apps taking camera access).
    ///
    /// - Note: Call this method when initializing the camera service.
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

    /// Removes notification observers for capture session events.
    ///
    /// This method cleans up all notification observers that were set up
    /// by `setupSessionObservers()`. It should be called when the camera
    /// service is no longer needed to prevent memory leaks.
    ///
    /// - Note: Call this method in `cleanupCamera()` or when deallocating.
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

        if !captureSession.isRunning && isCaptureSessionConfigured {
            Task {
                await start()
            }
        }
    }
}
