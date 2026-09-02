//
//  CameraService.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import CoreImage
import Foundation
import Metal
import SwiftUI

/// A comprehensive camera management service that provides unified access to device cameras
/// across iOS and macOS platforms with modern Swift concurrency support.
///
/// `CameraService` is a thin `@MainActor` facade over an internal `actor CameraEngine` that
/// owns the AVFoundation capture pipeline. All session mutations are serialized inside the
/// engine; the facade exposes `@Published` properties for SwiftUI and bridges async streams
/// for downstream consumers.
///
///
/// ## Architecture
/// - **Capture Operations**: Photo/video recording and session management live in
///   `CameraService+Capture.swift`, which trampolines to the engine.
/// - **Delegate Handling**: Internal delegate classes (`PhotoCaptureDelegate`,
///   `MovieRecordingDelegate`, `VideoDataOutputDelegate`) implement the AVFoundation
///   delegate protocols and forward results to the engine via continuations.
/// - **High-Level Intents**: User-friendly async APIs in `CameraService+Intents.swift`.
/// - **Permission Management**: `CameraService+Permissions.swift`.
/// - **Helpers**: `CameraService+Helpers.swift` contains snapshot accessors and stream
///   bridging helpers.
///
/// ## Usage
///
/// ```swift
/// let cameraService = CameraService(allowedCaptureModes: [.photo, .video])
/// await cameraService.initializeCamera()
///
/// let result = await cameraService.capturePhoto()
/// switch result {
/// case .success(let url):
///     print("Photo saved to: \(url)")
/// case .failure(let error):
///     print("Capture failed: \(error)")
/// }
/// ```
///
/// ## Thread Safety
///
/// The facade is `@MainActor`-isolated. All AVFoundation mutations are funneled through the
/// `CameraEngine` actor; this is enforced by the Swift compiler, not by convention.
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
/// - Some features (like flash) are iOS-only
///
@available(iOS 13.0, macOS 10.15, *)
@MainActor
public final class CameraService: ObservableObject {

    // MARK: - Core Properties

    /// The internal AVFoundation owner. All session mutations are serialized inside this actor.
    let engine: CameraEngine

    /// The active capture configuration.
    public let configuration: CaptureConfiguration

    /// The capture modes that are allowed by the configuration (photo and/or video).
    public var allowedCaptureModes: Set<CaptureMode> {
        configuration.allowedCaptureModes
    }

    // MARK: - Public Observable Properties

    /// The most recent preview frame as a SwiftUI `Image`.
    ///
    /// Updated on the main actor by `handleCameraPreviews()` which reads `previewStream`.
    @Published public var previewImage: Image?

    /// The width/height ratio of the most recent preview frame.
    ///
    /// Published alongside `previewImage` so consumers can drive an animated
    /// `aspectRatio` modifier: switching capture modes changes the session
    /// format (4:3 photo ↔ 16:9 video), and animating the ratio turns that
    /// layout change into a smooth resize instead of a jump.
    @Published public internal(set) var previewAspectRatio: CGFloat?

    /// Flash mode for photo capture (preserved when switching modes).
    var photoFlashMode: AVCaptureDevice.FlashMode = .off

    /// Torch mode for video recording (preserved when switching modes).
    var videoTorchMode: AVCaptureDevice.FlashMode = .off

    /// The current flash/torch mode reading the right backing variable for the current mode.
    public var flashMode: AVCaptureDevice.FlashMode {
        get { captureMode == .photo ? photoFlashMode : videoTorchMode }
        set {
            if captureMode == .photo {
                photoFlashMode = newValue
            } else {
                videoTorchMode = newValue
                // For video mode, activate/deactivate torch immediately (like iPhone Camera app)
                let mode = newValue
                Task { [engine] in
                    await engine.applyTorchImmediately(mode: mode)
                }
            }
        }
    }

    /// Indicates whether a photo capture operation is currently in progress.
    @Published public var isCapturingPhoto: Bool = false

    /// `true` while a capture-mode change is reconfiguring the session.
    ///
    /// Switching between photo and video commits a new session preset, which
    /// forces a device format change and briefly interrupts the frame flow.
    /// The camera interface uses this to soften the transition (defocusing
    /// the preview) while the engine settles the new format.
    @Published public internal(set) var isSwitchingCaptureMode = false

    /// Controls whether the camera preview is currently paused.
    ///
    /// When set to `true`, the preview stream stops delivering new frames
    /// but the capture session remains active. This can be useful for
    /// performance optimization or when the camera view is not visible.
    @Published public var isPreviewPaused: Bool = false {
        didSet {
            let paused = isPreviewPaused
            Task { [engine] in
                await engine.setPreviewPaused(paused)
            }
        }
    }

    /// The current capture mode (photo or video).
    ///
    /// This property tracks whether the camera interface is in photo or video mode.
    /// It's used to determine flash vs torch behavior and the session preset.
    /// When switching to video mode, torch is set to off by default.
    @Published public var captureMode: CaptureMode {
        didSet {
            // No-op sets (same mode) must not trigger an engine round-trip.
            let mode = captureMode
            guard oldValue != mode else { return }

            isSwitchingCaptureMode = true

            // Latest-wins: cancel the previous transition so only the newest
            // mode's engine run completes (the engine independently supersedes
            // overlapping runs) and only the non-superseded task clears the
            // published flag.
            captureModeTransitionTask?.cancel()
            captureModeTransitionTask = Task { [engine, weak self] in
                await engine.setCaptureModeForWiring(mode)
                await engine.applySessionPresetForMode(mode)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.isSwitchingCaptureMode = false
                }
            }
        }
    }

    /// The in-flight capture-mode transition task (see `captureMode.didSet`).
    /// Cancelled and cleared in `cleanupCamera()`.
    var captureModeTransitionTask: Task<Void, Never>?

    /// Indicates whether the camera session is currently interrupted
    /// (e.g., by a phone call or another app using the camera).
    @Published public var isSessionInterrupted: Bool = false

    /// The last session-level error (e.g., camera disconnected).
    /// Set automatically by runtime error handlers. Cleared on initialization and cleanup.
    @Published public var sessionError: CameraError?

    /// The number of lenses available on the active camera. Multi-lens
    /// (virtual) devices - dual and triple cameras - expose their constituent
    /// lenses here; single-lens devices report 1.
    @Published public internal(set) var lensCount: Int = 1

    /// The display magnification of each lens (e.g. `[0.5, 1, 3]`), aligned
    /// with `lensCount`. Empty on single-lens devices.
    @Published public internal(set) var lensMagnifications: [CGFloat] = []

    /// The index of the currently selected lens, in `0 ..< lensCount`.
    @Published public internal(set) var selectedLensIndex: Int = 0

    // MARK: - Public Computed Properties

    /// A Boolean value indicating whether the camera capture session is currently running.
    public var isRunning: Bool {
        engine.isRunningSnapshot()
    }

    /// A Boolean value indicating whether the front-facing camera is currently active.
    public var isUsingFrontCaptureDevice: Bool {
        engine.isUsingFrontCaptureDeviceNow()
    }

    /// A Boolean value indicating whether the back-facing camera is currently active.
    public var isUsingBackCaptureDevice: Bool {
        engine.isUsingBackCaptureDeviceNow()
    }

    /// A Boolean value indicating whether the current camera device supports flash.
    public var isFlashAvailable: Bool {
        engine.isFlashAvailableNow()
    }

    /// A Boolean value indicating whether the current camera device supports torch.
    public var isTorchAvailable: Bool {
        engine.isTorchAvailableNow()
    }

    /// The current authorization status for camera access.
    public var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// The current microphone authorization status.
    public var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// A Boolean value indicating whether any camera devices are available and authorized.
    public var isCameraAvailable: Bool {
        authorizationStatus == .authorized && !engine.availableCaptureDevices().isEmpty
    }

    /// A Boolean value indicating whether camera (and, when the configuration
    /// records audio, microphone) are available and authorized.
    public var isCameraAndMicrophoneAvailable: Bool {
        authorizationStatus == .authorized
            && (!configuration.capturesAudio || microphoneAuthorizationStatus == .authorized)
            && !engine.availableCaptureDevices().isEmpty
    }

    /// `true` when the movie file output is currently recording.
    public var isRecording: Bool {
        engine.isRecordingSnapshot()
    }

    /// The duration of the current recording, in seconds. Returns 0 when not recording.
    public var recordedDurationSeconds: Double {
        engine.recordedDurationSecondsSnapshot()
    }

    // MARK: - Async Streams

    /// An async stream that delivers live camera preview frames.
    ///
    /// Provides raw `CIImage` objects at approximately 30 FPS. The frames are
    /// sensor-oriented (not rotated or mirrored); the internal preview loop
    /// applies rotation and front-camera mirroring when building
    /// `previewImage`. The stream buffers only the newest frame, and is
    /// recreated on `cleanupCamera()`. Read-only for consumers — assigning it
    /// externally would desync the internal preview loop.
    public internal(set) var previewStream: AsyncStream<CIImage>!

    /// An async stream that delivers captured photos as they become available.
    /// Recreated on `cleanupCamera()` so subscriptions survive camera
    /// teardown/reopen cycles.
    public internal(set) var photoStream: AsyncStream<AVCapturePhoto>!

    /// An async stream that delivers URLs of completed video recordings.
    /// Recreated on `cleanupCamera()` so subscriptions survive camera
    /// teardown/reopen cycles.
    public internal(set) var movieFileStream: AsyncStream<URL>!

    // MARK: - Preview Handling

    var previewLoop: Task<Void, Never>?

    /// Observes device-orientation changes and re-derives the preview
    /// rotation (see `syncRotationFromDevice()`). Started by
    /// `initializeCamera()` and cancelled in `cleanupCamera()`.
    var orientationObservationTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a camera service with the given capture configuration.
    ///
    /// - Parameter configuration: Describes the allowed capture modes, photo
    ///   quality and resolution, initial camera position, and audio behavior.
    public init(configuration: CaptureConfiguration = CaptureConfiguration()) {
        // Photo is the preferred opening mode whenever it is allowed; the
        // mode set's iteration order is otherwise unspecified.
        let initialMode: CaptureMode =
            configuration.allowedCaptureModes.contains(.photo)
            ? .photo
            : (configuration.allowedCaptureModes.first ?? .photo)
        self.configuration = configuration
        self._captureMode = .init(initialValue: initialMode)

        // Create streams up front so consumers can subscribe before initializeCamera.
        // Newest-frame buffering: a slow consumer drops stale frames instead
        // of queueing them, keeping memory flat and the preview live.
        var previewContinuation: AsyncStream<CIImage>.Continuation!
        let previewStream = AsyncStream<CIImage>(bufferingPolicy: .bufferingNewest(1)) { previewContinuation = $0 }
        self.previewStream = previewStream

        var photoContinuation: AsyncStream<AVCapturePhoto>.Continuation!
        let photoStream = AsyncStream<AVCapturePhoto> { photoContinuation = $0 }
        self.photoStream = photoStream

        var movieContinuation: AsyncStream<URL>.Continuation!
        let movieStream = AsyncStream<URL> { movieContinuation = $0 }
        self.movieFileStream = movieStream

        // The engine starts with no state handler (`nil` is a no-op, exactly
        // like the placeholder object this used to build); the real one is
        // installed in the Task below once `self` is fully initialized.
        self.engine = CameraEngine(
            configuration: configuration,
            captureMode: initialMode,
            stateHandler: nil,
            previewStreamContinuation: previewContinuation,
            photoStreamContinuation: photoContinuation,
            movieStreamContinuation: movieContinuation
        )

        // Seed the engine's capture mode so the first wireSession picks the right preset.
        let engine = self.engine
        Task { [engine] in
            await engine.setCaptureModeForWiring(initialMode)
        }

        // Wire the real state handler so engine state changes update our
        // @Published properties. We do this in a Task because the closures
        // need to capture `self` after init has fully completed.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let realStateHandler = CameraEngineStateHandler(
                didInterrupt: { [weak self] in self?.isSessionInterrupted = true },
                didEndInterruption: { [weak self] in self?.isSessionInterrupted = false },
                didFail: { [weak self] error in self?.sessionError = error }
            )
            await self.engine.replaceStateHandler(realStateHandler)
        }
    }

    /// Creates a camera service restricted to the given capture modes, with
    /// all other configuration values at their defaults.
    ///
    /// - Parameter allowedCaptureModes: Capture modes available in the interface.
    public convenience init(allowedCaptureModes: Set<CaptureMode>) {
        self.init(configuration: CaptureConfiguration(allowedCaptureModes: allowedCaptureModes))
    }

    // MARK: - Internal Helpers

    /// Runs the preview → SwiftUI Image conversion loop.
    /// Called by `initializeCamera()` and re-armed after `cleanupCamera()`.
    ///
    /// Each frame is rendered to a `CGImage` with a shared `CIContext` before
    /// being published. This must happen eagerly: `UIImage(ciImage:)` wraps the
    /// `CIImage` lazily and has no `CGImage` backing, so SwiftUI's
    /// `Image(uiImage:)` has nothing to rasterize and the preview stays black.
    /// The loop runs detached from the main actor so the per-frame Core Image
    /// render doesn't block the UI.
    func handleCameraPreviews() async {
        guard previewLoop == nil else { return }
        let stream = previewStream!
        let engine = self.engine
        previewLoop = Task.detached(priority: .userInitiated) { [weak self] in
            // Prefer a Metal-backed context: rendering preview frames on the
            // GPU is considerably cheaper than the CPU path at 30fps. Falls
            // back to the default context where Metal is unavailable.
            let ciContext: CIContext
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                ciContext = CIContext(mtlDevice: metalDevice)
            } else {
                ciContext = CIContext()
            }
            for await rawImage in stream {
                guard let self, !Task.isCancelled else { return }

                // The video data output connection is pinned to 0° and never
                // mirrored (see `updateVideoOutputConnection`), so rotation and
                // front-camera mirroring are applied here on the raw buffer.
                // The angle is the preview rotation derived from the device
                // orientation (`syncRotationFromDevice`): it tracks how
                // the user is currently holding the device, so the live preview
                // stays upright and screen-filling in every orientation.
                // Photos and recordings use the separate coordinator *capture*
                // angle and are unaffected by this loop.
                let upright = rawImage.uprightPreview(
                    rotationAngle: engine.previewRotationAngle,
                    mirrored: engine.isUsingFrontCaptureDeviceNow()
                )
                guard let cgImage = ciContext.createCGImage(upright, from: upright.extent) else {
                    continue
                }
                let image = Image(decorative: cgImage, scale: 1, orientation: .up)
                let aspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                await MainActor.run {
                    if self.previewAspectRatio != aspectRatio {
                        self.previewAspectRatio = aspectRatio
                    }
                    self.previewImage = image
                }
            }
        }
    }

    // MARK: - Preview Rotation

    /// Maps the device orientation to the preview and capture rotation angles.
    ///
    /// Maps the device orientation to the preview rotation angle.
    ///
    /// This table owns the *preview* rotation on iOS (single writer); the
    /// *capture* rotation is owned by the engine's rotation coordinator
    /// (AVCam's architecture — see `CameraEngine.installRotationCoordinator`).
    /// The raw sensor buffer's intrinsic top is the phone's right edge in
    /// portrait, so portrait needs a 90° clockwise correction, and every 90°
    /// of device rotation offsets the angle by the same amount: portrait 90°,
    /// landscapeLeft (top edge left) 0°, landscapeRight 180°, upside-down
    /// 270°. The front camera's sensor is mounted differently, offsetting its
    /// correction by -90° (verified on hardware). The preview loop
    /// additionally mirrors the front camera for the natural selfie view.
    ///
    /// Values are normalized to 0..<360 so the `uprightPreview` orientation
    /// mapping always sees canonical angles.
    func syncRotationFromDevice() {
        #if os(iOS)
        let baseAngle: CGFloat
        switch UIDevice.current.orientation {
            case .portrait: baseAngle = 90
            case .portraitUpsideDown: baseAngle = 270
            case .landscapeLeft: baseAngle = 0
            case .landscapeRight: baseAngle = 180
            default: return  // faceUp/faceDown/unknown: keep the last angle
        }
        engine.previewRotationAngle = engine.isUsingFrontCaptureDeviceNow()
            ? (baseAngle - 90 + 360).truncatingRemainder(dividingBy: 360)
            : baseAngle
        #endif
    }

    func startObservingDeviceOrientationChanges() {
        #if os(iOS)
        guard orientationObservationTask == nil else { return }
        orientationObservationTask = Task { [weak self] in
            // Same availability gate the engine uses for its notification
            // streams; on older OS the preview rotation simply stays at its
            // seeded portrait value.
            if #available(iOS 15.0, *) {
                for await _ in NotificationCenter.default.notifications(
                    named: UIDevice.orientationDidChangeNotification
                ) {
                    guard let self, !Task.isCancelled else { return }
                    self.syncRotationFromDevice()
                }
            }
        }
        #endif
    }
}

// MARK: - Preview Frame Conversion

@available(iOS 13.0, macOS 10.15, *)
extension CIImage {
    /// Rotates a raw (0°) sensor buffer upright for preview display and
    /// optionally mirrors it horizontally (front camera).
    ///
    /// `rotationAngle` is the clockwise correction for the current device
    /// orientation (the preview rotation - see `syncRotationFromDevice`),
    /// or 90 by default on OS versions without device-orientation tracking.
    fileprivate func uprightPreview(rotationAngle: CGFloat, mirrored: Bool) -> CIImage {
        let orientation: CGImagePropertyOrientation
        switch rotationAngle {
            case 90: orientation = .right
            case 180: orientation = .down
            case 270: orientation = .left
            default: orientation = .up
        }
        let upright = oriented(orientation)
        guard mirrored else { return upright }

        // Horizontal flip within the same extent: x → width - x.
        return
            upright
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: upright.extent.width, y: 0))
    }
}
