//
//  CameraCaptureView.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import AVKit
import CoreImage
import SwiftUI

// MARK: - Camera Capture View

/// A complete SwiftUI camera interface with live preview, capture controls,
/// and mode switching for both photo and video recording.
///
/// The `CameraCaptureView` provides a production-ready camera UI with:
/// - Live camera preview with proper aspect ratio
/// - Photo/video mode switching with animated transitions
/// - Flash control with visual availability indicators
/// - Camera switching between front and back devices
/// - Permission handling with user-friendly alerts
///
/// ## Usage
///
/// ```swift
/// CameraCaptureView { result in
///     switch result {
///     case .success(let url):
///         // Handle captured media
///         print("Media saved to: \(url)")
///     case .failure(let error):
///         // Handle errors
///         print("Capture failed: \(error)")
///     }
/// }
/// ```
///
/// ## Platform Availability
///
/// - iOS 14.0+
/// - macOS 11.0+
/// - Some features (like flash) are iOS-only
@available(iOS 14.0, macOS 11.0, *)
public struct CameraCaptureView: View {
    @StateObject private var cameraService = CameraService()
    @State private var isRecording = false
    @State private var showingPermissionAlert = false

    /// Callback closure that handles the result of camera capture operations.
    ///
    /// This closure is called when a photo is captured or video recording completes.
    /// It provides a `Result<URL, CameraError>` containing either the URL
    /// to the captured media file or error information.
    ///
    /// - Parameters:
    ///   - result: The result of the capture operation containing either the media URL or error.
    @MainActor
    public let onCapture: (Result<URL, CameraError>) -> Void

    /// Creates a new camera capture view with a capture completion handler.
    ///
    /// This initializer sets up the camera interface with the specified completion handler
    /// that will be called when photos are captured or videos finish recording.
    ///
    /// - Parameter onCapture: A closure that handles the result of capture operations.
    public init(onCapture: @escaping (Result<URL, CameraError>) -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        if #available(iOS 15.0, macOS 11.0, *) {
            viewBody
                #if os(iOS)
            .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
                Button("Cancel") {
                    onCapture(.failure(CameraError.userCancelled))
                }
                Button("Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
            } message: {
                Text("Please enable camera access in Settings to use this feature.")
            }
                #endif
        } else {
            viewBody
        }
    }

    var viewBody: some View {
        ZStack {
            cameraService.previewImage?
                .resizable()
                .aspectRatio(contentMode: .fit)

            VStack {
                topControls
                Spacer()
                bottomControls
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
        .background(Color.black.ignoresSafeArea(.all))
        .onAppear {
            Task { await initializeCamera() }
        }
        .onDisappear {
            cameraService.cleanupCamera()
        }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack {
            closeButton
            Spacer()
            flashButton
        }
        .overlay {
            if cameraService.movieFileOutput?.isRecording ?? false {
                RecordingTimeView(time: cameraService.movieFileOutput?.recordedDuration.seconds ?? 0)
            } else {
                modeSelector
                    .frame(maxWidth: 100)
            }
        }
    }

    var closeButton: some View {
        Button(
            action: {
                onCapture(.failure(CameraError.userCancelled))
            },
            label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .padding()
                    .grayBackgroundCircle()
            }
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            Spacer(minLength: 44)
            cameraSwitchButton
        }
        .overlay {
            captureButton
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        Picker("Capture Mode", selection: $cameraService.captureMode) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Label(mode.rawValue, systemImage: mode.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Flash Button

    private var flashButton: some View {
        Button(action: cameraService.toggleFlashMode) {
            Image(systemName: flashIcon)
                .foregroundColor(flashIconColor)
                .padding()
                .grayBackgroundCircle()
        }
        .disabled(!cameraService.isCameraAvailable)
    }

    private var flashIcon: String {
        guard cameraService.isFlashAvailable else {
            return "bolt.trianglebadge.exclamationmark"
        }

        switch cameraService.flashMode {
            case .on:
                return "bolt.fill"
            case .auto:
                return "bolt.badge.automatic"
            case .off:
                return "bolt.slash"
            @unknown default:
                return "bolt.slash"
        }
    }

    private var flashIconColor: Color {
        guard cameraService.isFlashAvailable else {
            return .orange
        }

        // During video recording, show torch status
        if cameraService.captureMode == .video && cameraService.movieFileOutput?.isRecording == true {
            if cameraService.isTorchAvailable {
                switch cameraService.flashMode {
                case .on:
                    return .yellow
                case .auto:
                    return .blue
                case .off:
                    return .white
                @unknown default:
                    return .white
                }
            } else {
                return .gray
            }
        }

        // Photo mode - show flash status
        switch cameraService.flashMode {
            case .on:
                return .yellow
            case .auto:
                return .blue
            case .off:
                return .white
            @unknown default:
                return .white
        }
    }

    // MARK: - Camera Switch Button

    private var cameraSwitchButton: some View {
        Button(action: {
            withAnimation {
                cameraService.switchCamera()
            }
        }) {
            Image(systemName: "camera.rotate")
                .foregroundColor(.white)
                .padding()
                .grayBackgroundCircle()
        }
        .disabled(!cameraService.isCameraAvailable)
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button(action: {
            if cameraService.captureMode == .photo {
                capturePhoto()
            } else {
                toggleVideoRecording()
            }
        }) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 70, height: 70)
                    .padding(4)
                    .grayBackgroundCircle()

                if isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Circle()
                        .fill(cameraService.captureMode == .video ? .red : .black)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(cameraService.isCapturingPhoto || !cameraService.isCameraAvailable)
    }

    // MARK: - Actions

    private func initializeCamera() async {
        let result = await cameraService.initializeCamera()

        switch result {
            case .success:
                print("Camera initialized successfully")
            case .failure(let error):
                print("Failed to initialize camera: \(error.localizedDescription)")
                if error == CameraError.permissionDenied {
                    showingPermissionAlert = true
                } else {
                    print(error.errorDescription ?? "Failed to initialize camera")
                    onCapture(.failure(error))
                }
        }
    }

    private func capturePhoto() {
        Task {
            let result = await cameraService.capturePhotoWithCompletion()

            await MainActor.run {
                switch result {
                    case .success(let url):
                        onCapture(.success(url))
                    case .failure(let error):
                        print(error.errorDescription ?? "Failed to capture photo")
                        onCapture(.failure(error))
                }
            }
        }
    }

    private func toggleVideoRecording() {
        if isRecording {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        let result = cameraService.startVideoRecording()

        switch result {
            case .success:
                withAnimation {
                    isRecording = true
                }
            case .failure(let error):
                print(error.errorDescription ?? "Failed to start recording")
        }
    }

    private func stopVideoRecording() {
        cameraService.stopRecordingVideo()

        // Listen for video file completion
        Task {
            for await url in cameraService.movieFileStream {
                await MainActor.run {
                    withAnimation {
                        isRecording = false
                    }
                    onCapture(.success(url))
                }
                break
            }
        }
    }
}
