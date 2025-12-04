//
//  CameraCaptureView.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import CoreImage
import SwiftUI

// MARK: - Capture Mode

public enum CaptureMode: String, CaseIterable {
    case photo = "photo"
    case video = "video"

    var systemImage: String {
        switch self {
            case .photo:
                return "camera"
            case .video:
                return "video"
        }
    }
}

// MARK: - Camera Capture View
@available(iOS 14.0, macOS 11.0, *)
public struct CameraCaptureView: View {
    @StateObject private var cameraService = CameraService()
    @State private var captureMode: CaptureMode = .photo
    @State private var isRecording = false
    @State private var isFlashOn = false
    @State private var showingPermissionAlert = false

    @MainActor
    public let onCapture: (Result<URL, CameraError>) -> Void

    public init(onCapture: @escaping (Result<URL, CameraError>) -> Void) {
        self.onCapture = onCapture
    }

    public var body: some View {
        if #available(iOS 15.0, macOS 11.0, *) {
            viewBody
            #if os(iOS)
                .alert("Camera Access Required", isPresented: $showingPermissionAlert) {
                    Button("Cancel") {
                        onCapture(.failure(CameraError.permissionDenied))
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
            // Camera preview
            cameraService.previewImage?
                .resizable()
                .aspectRatio(contentMode: .fit)

            // UI Controls overlay
            VStack {
                // Top controls
                topControls

                Spacer()

                // Bottom controls
                bottomControls
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
        }
        .background(Color.black)
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
            // Close button
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

            Spacer()

            // Mode selector
            modeSelector

            Spacer()

            // Flash button
            flashButton
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 50) {
            // Camera switch button
            cameraSwitchButton

            // Capture button
            captureButton

            // Spacer (no gallery button as requested)
            Spacer()
                .frame(width: 44)
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 20) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button(
                    action: {
                        withAnimation {
                            captureMode = mode
                        }
                    },
                    label: {
                        Image(systemName: mode.systemImage)
                            .foregroundColor(captureMode == mode ? .blue : .white)
                            .padding()
                            .grayBackgroundCircle()
                            .overlay(
                                Circle()
                                    .stroke(captureMode == mode ? .blue : .clear, lineWidth: 2)
                            )
                    }
                )
            }
        }
    }

    // MARK: - Flash Button

    private var flashButton: some View {
        Button(action: {
            isFlashOn = cameraService.toggleFlashMode()
        }) {
            Image(systemName: flashIcon)
                .foregroundColor(isFlashOn ? .yellow : .white)
                .padding()
                .grayBackgroundCircle()
        }
        .disabled(!cameraService.getCameraInfo().isAvailable)
    }

    private var flashIcon: String {
        switch cameraService.currentFlashMode {
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
        .disabled(!cameraService.getCameraInfo().isAvailable)
    }

    // MARK: - Capture Button

    private var captureButton: some View {
        Button(action: {
            if captureMode == .photo {
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
                        .fill(captureMode == .video ? .red : .black)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .disabled(cameraService.isLoading || !cameraService.getCameraInfo().isAvailable)
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
