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

    public var authorizationStatus: AVAuthorizationStatus = .notDetermined
    public var isCameraAvailable: Bool = false
    public var isLoading: Bool = false
    public var isPreviewPaused = false

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

    public var isRunning: Bool {
        captureSession.isRunning
    }

    public var isUsingFrontCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return frontCaptureDevices.contains(captureDevice)
    }

    public var isUsingBackCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return backCaptureDevices.contains(captureDevice)
    }

    // MARK: - Async Streams

    var addToPhotoStream: ((AVCapturePhoto) -> Void)?

    var photoStream: AsyncStream<AVCapturePhoto> {
        AsyncStream { continuation in
            addToPhotoStream = { photo in
                continuation.yield(photo)
            }
        }
    }

    var addToMovieFileStream: ((URL) -> Void)?

    public var movieFileStream: AsyncStream<URL> {
        AsyncStream { continuation in
            addToMovieFileStream = { fileUrl in
                continuation.yield(fileUrl)
            }
        }
    }

    var addToPreviewStream: ((CIImage) -> Void)?

    public var previewStream: AsyncStream<CIImage> {
        AsyncStream { continuation in
            addToPreviewStream = { ciImage in
                if !self.isPreviewPaused {
                    continuation.yield(ciImage)
                }
            }
        }
    }

    // for preview camera output
    func handleCameraPreviews() async {
        let imageStream =
            previewStream
            .map { $0.image }

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

        // Check initial camera availability
        checkCameraAvailability()

        print("CameraService initialized")
    }

    // MARK: - Private Helper Methods

    private func checkCameraAvailability() {
        isCameraAvailable = !availableCaptureDevices.isEmpty
    }

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

        if #available(iOS 13.0, macOS 13.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .quality
        } else {
            // Fallback on earlier versions
        }

        updateVideoOutputConnection()

        isCaptureSessionConfigured = true
        success = true

        print("Capture session configured successfully")
    }
}

// MARK: - Rotation Angle (from provided code)

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
