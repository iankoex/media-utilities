//
//  CameraService+Helpers.swift
//  MediaUtilities
//
//  Created by ian on 06/12/2025.
//

import AVFoundation
import CoreImage
import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
extension CameraService {
    // MARK: - Private Helper Methods

    @concurrent
    func handleCameraPreviews() async {
        let imageStream = previewStream.map { $0.image }

        for await image in imageStream {
            await MainActor.run {
                previewImage = image
            }
        }
    }

    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        return try? AVCaptureDeviceInput(device: validDevice)
    }

    func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
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

        // Re-add audio input if available
        if let audioDevice = audioDevice,
            let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
            !captureSession.inputs.contains(audioInput),
            captureSession.canAddInput(audioInput)
        {
            captureSession.addInput(audioInput)
            self.audioInput = audioInput
        }

        // Reset zoom factor to 1.0 for consistent default zoom
        #if os(iOS)
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.videoZoomFactor != 1.0 {
                captureDevice.videoZoomFactor = 1.0
            }
            captureDevice.unlockForConfiguration()
        } catch {
            // Zoom reset failed - continue silently
        }
        #endif

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
            return
        }

        let movieFileOutput = AVCaptureMovieFileOutput()
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))

        guard captureSession.canAddInput(deviceInput) else {
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            return
        }
        guard captureSession.canAddOutput(videoOutput) else {
            return
        }

        captureSession.addInput(deviceInput)

        // Add audio input for video recording with audio
        if let audioDevice = audioDevice,
            let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
            captureSession.canAddInput(audioInput)
        {
            captureSession.addInput(audioInput)
            self.audioInput = audioInput
        }

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
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension CIImage {
    fileprivate var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}
