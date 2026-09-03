//
//  CameraCaptureView.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
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
/// var configuration = CaptureConfiguration()
/// configuration.allowedCaptureModes = [.photo, .video]
/// configuration.photoDimensions = .maximum
/// configuration.photoQuality = .quality
///
/// CameraCaptureView(configuration: configuration) { result in
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
    @State private var showingPermissionAlert = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var lensLabelSize: CGFloat = 13

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

    /// Creates a new camera capture view with a capture configuration.
    ///
    /// The configuration describes everything customizable about the capture
    /// pipeline: allowed capture modes, photo quality and resolution, the
    /// camera active on first open, and whether video recordings include
    /// audio. Defaults provide photo + video modes, fast `.balanced` stills,
    /// and the back camera.
    ///
    /// - Parameters:
    ///   - configuration: Describes how the camera pipeline behaves.
    ///   - onCapture: A closure that handles the result of capture operations.
    public init(
        configuration: CaptureConfiguration = CaptureConfiguration(),
        onCapture: @escaping (Result<URL, CameraError>) -> Void
    ) {
        self.onCapture = onCapture
        self._cameraService = StateObject(wrappedValue: CameraService(configuration: configuration))
    }

    /// Creates a new camera capture view restricted to the given capture
    /// modes, with all other configuration values at their defaults.
    ///
    /// - Parameters:
    ///   - allowedCaptureModes: A set of capture modes that should be available in the camera interface.
    ///     Defaults to `[.photo, .video]` to allow both photo and video capture.
    ///     Use `[.photo]` to restrict to photo-only or `[.video]` for video-only.
    ///   - onCapture: A closure that handles the result of capture operations.
    public init(
        allowedCaptureModes: Set<CaptureMode> = [.photo, .video],
        onCapture: @escaping (Result<URL, CameraError>) -> Void
    ) {
        self.init(
            configuration: CaptureConfiguration(allowedCaptureModes: allowedCaptureModes),
            onCapture: onCapture
        )
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
                // Runtime failures (camera disconnected, media-services reset)
                .onChange(of: cameraService.sessionError) { error in
                    if let error = error {
                        cameraService.sessionError = nil
                        onCapture(.failure(error))
                    }
                }
        } else {
            viewBody
        }
    }

    var viewBody: some View {
        ZStack {
            cameraService.previewImage?
                .resizable()
                // The frame's aspect changes with the session format on
                // capture-mode switches (4:3 ↔ 16:9); animating an explicit
                // ratio turns the layout change into a smooth resize instead
                // of a jump.
                .aspectRatio(cameraService.previewAspectRatio, contentMode: .fit)
                .animation(.easeInOut(duration: 0.2), value: cameraService.previewAspectRatio)
                // Capture-mode changes reconfigure the session (new preset,
                // device format, lens restore), which freezes the frame flow
                // for a moment. Defocusing the preview across that window
                // turns the two hard cuts (freeze-in, unfreeze) into a single
                // defocus/refocus transition. With Reduce Motion on, only the
                // dim changes.
                .blur(radius: cameraService.isSwitchingCaptureMode && !reduceMotion ? 20 : 0)
                .opacity(cameraService.isSwitchingCaptureMode ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.2), value: cameraService.isSwitchingCaptureMode)
                .padding(.top)

            // Interruption overlay
            if cameraService.isSessionInterrupted {
                Color.black.opacity(0.6)
                    .ignoresSafeArea(.all)
                VStack(spacing: 12) {
                    Image(systemName: "video.slash.fill")
                        .font(.largeTitle)
                    Text("Camera Unavailable")
                        .font(.title2.weight(.semibold))
                    Text("Another app may be using the camera.")
                        .font(.subheadline)
                }
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(40)
            }

            VStack {
                topControls
                Spacer()
                bottomControls
            }
            .padding(.horizontal)
        }
        .background(Color.black.ignoresSafeArea(.all))
        .onAppear {
            Task { await initializeCamera() }
        }
        .onDisappear {
            Task { await cameraService.cleanupCamera() }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .frame(minHeight: 500)
        #endif
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack {
            closeButton
            Spacer()
            flashButton
        }
        .overlay {
            if cameraService.isRecording {
                // Driven by its own clock, not by `previewImage`
                // republication — a paused or stalled preview must never
                // freeze the recording timer.
                RecordingTimeView(timeProvider: { cameraService.recordedDurationSeconds })
            } else if cameraService.allowedCaptureModes.count > 1 {
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
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.white)
                    .padding(5)
                    .grayBackgroundCircle()
            }
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            Spacer(minLength: 44)
            if cameraService.configuration.showsLensSwitcher {
                lensButton
            }
            cameraSwitchButton
        }
        .overlay {
            captureButton
        }
        .padding(.bottom, 20)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        Picker("Capture Mode", selection: $cameraService.captureMode) {
            ForEach(cameraService.allowedCaptureModes.sorted(by: { $0.rawValue < $1.rawValue })) { mode in
                Label(mode.rawValue, systemImage: mode.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        // A mode switch reconfigures the session and resets the lens; taps
        // during the transition would race the automatic lens restore.
        .disabled(
            cameraService.previewImage == nil || cameraService.isRecording || cameraService.isSwitchingCaptureMode
        )
    }

    // MARK: - Flash Button

    private var flashButton: some View {
        Button("Flash", systemImage: flashIcon) {
            Task { await cameraService.toggleFlashMode() }
        }
        .labelStyle(.iconOnly)
        .foregroundColor(flashIconColor)
        .padding(5)
        .grayBackgroundCircle()
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
        if cameraService.captureMode == .video && cameraService.isRecording {
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

    // MARK: - Lens Button

    /// Shown only when the active camera is a multi-lens (virtual) device -
    /// dual and triple cameras - and the configuration enables the lens
    /// switcher. Displays the current lens magnification (e.g. 1×); tapping
    /// shuffles to the next available lens in ascending order (1× → 2× → 3×
    /// → 0.5× → 1×).
    @ViewBuilder
    private var lensButton: some View {
        if let label = currentLensLabel {
            Button(action: {
                Task {
                    await cameraService.switchLens()
                }
            }) {
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(5)
                    .grayBackgroundCircle()
            }
            .accessibilityLabel("Switch lens")
            .disabled(
                !cameraService.isCameraAvailable || cameraService.isRecording || cameraService.isSwitchingCaptureMode
            )
        }
    }

    /// The magnification label of the currently selected lens, or `nil` when
    /// the active camera has fewer than two lenses.
    private var currentLensLabel: String? {
        guard cameraService.lensCount > 1,
            cameraService.lensMagnifications.count == cameraService.lensCount,
            cameraService.lensMagnifications.indices.contains(cameraService.selectedLensIndex)
        else { return nil }

        return lensLabel(for: cameraService.lensMagnifications[cameraService.selectedLensIndex])
    }

    /// Formats a lens magnification for display: whole numbers render without
    /// decimals (1×, 3×), fractional ones keep a decimal (0.5×).
    private func lensLabel(for factor: CGFloat) -> String {
        let roundedToTenth = (factor * 10).rounded() / 10
        let number =
            roundedToTenth == roundedToTenth.rounded()
            ? String(Int(roundedToTenth))
            : String(format: "%.1f", roundedToTenth)
        return number + "×"
    }

    // MARK: - Camera Switch Button

    private var cameraSwitchButton: some View {
        Button(action: {
            Task {
                await cameraService.switchCamera()
            }
        }) {
            Label("Rotate Camera", systemImage: "camera.rotate")
                .labelStyle(.iconOnly)
                .foregroundColor(.white)
                .padding(5)
                .grayBackgroundCircle()
        }
        .disabled(!cameraService.isCameraAvailable || cameraService.isRecording)
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
                    .frame(width: 55, height: 55)
                    .grayBackgroundCircle()

                if cameraService.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 45, height: 45)
                } else {
                    Circle()
                        .fill(cameraService.captureMode == .video ? .red : .black)
                        .frame(width: 50, height: 50)
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
                break
            case .failure(let error):
                if error == CameraError.permissionDenied || error == CameraError.microphonePermissionDenied {
                    showingPermissionAlert = true
                } else {
                    onCapture(.failure(error))
                }
        }
    }

    private func capturePhoto() {
        Task {
            let result = await cameraService.capturePhoto()

            await MainActor.run {
                switch result {
                    case .success(let url):
                        onCapture(.success(url))
                    case .failure(let error):
                        onCapture(.failure(error))
                }
            }
        }
    }

    private func toggleVideoRecording() {
        if cameraService.isRecording {
            stopVideoRecording()
        } else {
            startVideoRecording()
        }
    }

    private func startVideoRecording() {
        Task {
            let result = await cameraService.startVideoRecording()

            await MainActor.run {
                switch result {
                    case .success:
                        break
                    case .failure(let error):
                        guard !cameraService.isRecording else { return }
                        onCapture(.failure(error))
                }
            }
        }
    }

    private func stopVideoRecording() {
        Task {
            let result = await cameraService.stopVideoRecording()

            await MainActor.run {
                switch result {
                    case .success(let url):
                        onCapture(.success(url))
                    case .failure(let error):
                        guard cameraService.isRecording else { return }
                        onCapture(.failure(error))
                }
            }
        }
    }
}
