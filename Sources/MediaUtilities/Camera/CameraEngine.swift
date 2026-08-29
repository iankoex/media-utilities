//
//  CameraEngine.swift
//  MediaUtilities
//
//  Created by ian on 26/08/2026.
//

// AVFoundation's capture classes are documented as thread-safe but are not
// yet annotated `Sendable`; `@preconcurrency` scopes that mismatch to this
// file until the Swift 6 migration pass restructures the notification tasks.
@preconcurrency import AVFoundation
import CoreImage
import Foundation

#if os(iOS)
import AudioToolbox
#endif

/// The internal AVFoundation owner.
///
/// `CameraEngine` is an `actor` that owns the capture session, inputs, outputs,
/// and all mutable configuration state. All AVFoundation work happens inside
/// this actor; the public `CameraService` is a thin `@MainActor` facade that
/// forwards to it. The actor's executor is backed by a serial dispatch queue
/// to preserve the existing serialization guarantees on the AVFoundation side.
///
@available(iOS 13.0, macOS 10.15, *)
actor CameraEngine {

    // MARK: - Owned AVFoundation State

    let captureSession = AVCaptureSession()
    var deviceInput: AVCaptureDeviceInput?
    var audioInput: AVCaptureDeviceInput?
    var photoOutput: AVCapturePhotoOutput?
    var videoOutput: AVCaptureVideoDataOutput?
    var videoDataOutputDelegate: VideoDataOutputDelegate?
    var isCaptureSessionConfigured = false

    /// Accessor for the movie file output. Backed by `movieFileOutputHolder`
    /// so `nonisolated` snapshot methods can read it. Inside the actor, write
    /// `movieFileOutputHolder.output = ...` directly.
    var movieFileOutput: AVCaptureMovieFileOutput? {
        get { movieFileOutputHolder.output }
        set { movieFileOutputHolder.output = newValue }
    }

    /// Holder for the currently-active capture device. Set inside the actor
    /// (init, `switchCamera`, recovery paths) and read by `nonisolated` snapshot
    /// helpers on the facade. `AVCaptureDevice` reads are documented as
    /// thread-safe; only writes happen on the actor.
    let currentDeviceHolder: DeviceHolder

    /// Holder for the movie file output, allowing `nonisolated` snapshot reads.
    let movieFileOutputHolder: MovieOutputHolder

    /// Holder for the engine's intended capture mode, allowing `nonisolated` reads.
    let captureModeHolder: CaptureModeHolder

    final class DeviceHolder: @unchecked Sendable {
        var device: AVCaptureDevice?
        init(_ device: AVCaptureDevice?) { self.device = device }
    }

    final class MovieOutputHolder: @unchecked Sendable {
        var output: AVCaptureMovieFileOutput?
        init(_ output: AVCaptureMovieFileOutput? = nil) { self.output = output }
    }

    final class CaptureModeHolder: @unchecked Sendable {
        var mode: CaptureMode
        init(_ mode: CaptureMode) { self.mode = mode }
    }

    // MARK: - Rotation Coordinator

    /// The rotation coordinator for the current capture device. Recreated
    /// whenever the active device changes. The coordinator is KVO-observed to
    /// apply the correct rotation to the photo and movie output connections
    /// when the device orientation changes. Only available on iOS 17+ / macOS 14+.
    var rotationCoordinator: AnyObject?

    /// A `AVCaptureVideoPreviewLayer` we create solely so the rotation
    /// coordinator has a layer to compute against. We don't add this layer to
    /// a view hierarchy, so its geometry is synthetic and only the
    /// coordinator's *capture* angle is meaningful - which is the only one we
    /// consume. Created once and reused across camera switches: a
    /// freshly-created layer has no established session connection yet, and
    /// computing the seed angle against it mis-seeds the back camera's angle
    /// as 0° until the coordinator's KVO fires some moments later. Retained
    /// on the engine for the lifetime of the session.
    var coordinatorPreviewLayer: AVCaptureVideoPreviewLayer?

    /// KVO observations attached to the rotation coordinator. Held strongly
    /// so the observation lives as long as the engine.
    var rotationObservations: [NSKeyValueObservation] = []

    /// KVO observation of the active device's `activeFormat`. A format change
    /// (e.g. from a session-preset change when switching capture modes) resets
    /// the device's zoom to its default; the observer re-applies the retained
    /// lens at the moment the new format lands.
    var activeFormatObservation: NSKeyValueObservation?

    /// The latest `videoRotationAngleForHorizonLevelCapture` reported by the
    /// coordinator. Read by `dispatchPhotoCapture` and
    /// `applyCaptureRotationToPhotoAndMovieOutputs` to apply the correct
    /// rotation to photos and recordings. This is the angle that makes
    /// *captured media* come out straight - it must not be used for the live
    /// preview, which follows the user's grip via `previewRotationAngle`.
    /// Defaults to 90 (portrait) on iOS and 0 on macOS, where camera frames
    /// are natively upright (the coordinator reports 0 there too).
    nonisolated(unsafe) var captureRotationAngle: CGFloat = CameraEngine.defaultCaptureRotationAngle

    /// The rotation that keeps the live preview upright relative to how the
    /// user is currently holding the device. Derived from `UIDeviceOrientation`
    /// by the facade (`syncPreviewRotationFromDevice`) on iOS; on macOS it
    /// stays at 0, since camera frames are natively upright and there is no
    /// held-device orientation to track. Written by the facade on the main
    /// actor, read per frame by the preview loop - word-sized writes with
    /// benign tearing, same rationale as `captureRotationAngle`.
    nonisolated(unsafe) var previewRotationAngle: CGFloat = CameraEngine.defaultPreviewRotationAngle

    /// Default rotation corrections before the coordinator seeds the capture
    /// angle and while no device-orientation sync has run: iOS portraits need
    /// 90° clockwise; macOS camera frames need none.
    #if os(macOS)
    private static let defaultCaptureRotationAngle: CGFloat = 0
    private static let defaultPreviewRotationAngle: CGFloat = 0
    #else
    private static let defaultCaptureRotationAngle: CGFloat = 90
    private static let defaultPreviewRotationAngle: CGFloat = 90
    #endif

    /// Creates a new rotation coordinator for the given device and observes it.
    /// On iOS 17+ / macOS 14+ this drives the rotation automatically and
    /// follows device orientation. On older OS, no rotation is applied (the
    /// camera outputs the sensor-native orientation).
    func installRotationCoordinator(for device: AVCaptureDevice) {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }

        // Drop previous observations before installing a new coordinator. The
        // preview layer is deliberately *not* dropped - it is created once and
        // reused (see `coordinatorPreviewLayer`).
        rotationObservations.removeAll()
        rotationCoordinator = nil

        // We don't render the preview via `AVCaptureVideoPreviewLayer` (we use a
        // `CIImage`/`Image` SwiftUI path), but the rotation coordinator needs
        // *a* layer to compute against - without one, the back camera's capture
        // angle falls back to 0. The layer is created on first use and reused
        // for every subsequent coordinator: computing against a brand-new
        // layer (no established connection yet) mis-seeds the back camera's
        // angle as 0° after a switch, which shows as a briefly rotated preview
        // until the coordinator self-corrects via KVO. The layer is never
        // added to a view hierarchy; only its established connection matters.
        let previewLayer: AVCaptureVideoPreviewLayer
        if let existing = coordinatorPreviewLayer {
            previewLayer = existing
        } else {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspect
            coordinatorPreviewLayer = previewLayer
        }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)

        // Seed the capture angle. The capture angle is the horizon-level angle
        // for raw buffers - the value that makes photos and recordings come
        // out straight. The preview angle is deliberately NOT taken from the
        // coordinator (see `previewRotationAngle`); the facade derives it from
        // the device orientation instead.
        captureRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture

        // Observe capture rotation. This keeps photos and recordings tracking
        // device-orientation changes.
        let captureObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let angle = change.newValue else { return }
            self.captureRotationAngle = angle
        }
        rotationObservations.append(captureObservation)

        rotationCoordinator = coordinator

        // Apply the initial capture rotation to the photo and movie connections
        // (they're already added by wireSession by this point).
        applyCaptureRotationToPhotoAndMovieOutputs()
    }

    /// Observes the active device's `activeFormat` so the engine can react when
    /// the session re-selects the device format (e.g. when a capture-mode
    /// switch commits a new session preset). See `activeFormatDidChange(deviceID:)`.
    func installActiveFormatObserver(for device: AVCaptureDevice) {
        activeFormatObservation?.invalidate()
        activeFormatObservation = nil

        #if os(iOS)
        // Capture only the device's identity: `AVCaptureDevice` is not
        // `Sendable`, so the observation closure forwards an
        // `ObjectIdentifier` into the actor-bound task instead of the
        // device itself.
        let deviceID = ObjectIdentifier(device)
        activeFormatObservation = device.observe(\.activeFormat, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { await self.activeFormatDidChange(deviceID: deviceID) }
        }
        #endif
    }

    /// Called when the active device's `activeFormat` changes. The session
    /// reconfigures the device's format when its preset changes (the two are
    /// mutually exclusive per AVFoundation), and a format change resets the
    /// device's zoom to its default - the 0.5× ultra-wide on multi-lens
    /// devices. Re-applies the retained lens at the moment the reset lands,
    /// and bumps the generation counter so the preset-change settle wait (see
    /// `applySessionPresetForMode`) knows the reset has been handled.
    func activeFormatDidChange(deviceID: ObjectIdentifier) {
        guard let device = currentDeviceHolder.device,
            ObjectIdentifier(device) == deviceID
        else { return }

        #if os(iOS)
        selectLens(at: selectedLensIndexHolder.value, ramping: false)
        formatChangeGenerationHolder.value += 1
        #endif
    }

    /// Convenience accessor used inside the actor.
    var currentDevice: AVCaptureDevice? {
        get { currentDeviceHolder.device }
        set { currentDeviceHolder.device = newValue }
    }

    // MARK: - Configuration (inputs from the facade)

    /// The active capture configuration. Drives device discovery, the photo
    /// capture settings, and audio wiring.
    let configuration: CaptureConfiguration

    /// The capture modes allowed by the configuration.
    var allowedCaptureModes: Set<CaptureMode> {
        configuration.allowedCaptureModes
    }

    // MARK: - Continuations and Streams

    var previewStreamContinuation: AsyncStream<CIImage>.Continuation?
    var photoStreamContinuation: AsyncStream<AVCapturePhoto>.Continuation?
    var movieStreamContinuation: AsyncStream<URL>.Continuation?

    // MARK: - State Forwarding

    /// Holder for the state-update handler. Wrapped in a reference type so it
    /// can be set from outside the actor (the facade installs the real handler
    /// after `init` finishes; the engine reads it when state changes occur).
    let stateHandlerHolder: StateHandlerHolder

    final class StateHandlerHolder: @unchecked Sendable {
        var handler: CameraEngineStateHandler?
        init(_ handler: CameraEngineStateHandler? = nil) { self.handler = handler }
    }

    func replaceStateHandler(_ handler: CameraEngineStateHandler) {
        stateHandlerHolder.handler = handler
    }

    /// Convenience accessor used inside the actor.
    var stateHandler: CameraEngineStateHandler? {
        stateHandlerHolder.handler
    }

    // MARK: - Executor
    //
    // Pinning the actor to a dedicated serial dispatch queue (via
    // `_DispatchSerialExecutorQueue.asUnownedSerialExecutor()`) requires
    // iOS 17 / macOS 14. Our deployment target is iOS 13 / macOS 10.15, so we
    // use the default actor executor. Concurrency safety is preserved (the
    // actor still serializes all calls); only the queue is different.

    // MARK: - Init

    init(
        configuration: CaptureConfiguration,
        captureMode: CaptureMode,
        stateHandler: CameraEngineStateHandler?,
        previewStreamContinuation: AsyncStream<CIImage>.Continuation,
        photoStreamContinuation: AsyncStream<AVCapturePhoto>.Continuation,
        movieStreamContinuation: AsyncStream<URL>.Continuation
    ) {
        self.configuration = configuration
        self.previewStreamContinuation = previewStreamContinuation
        self.photoStreamContinuation = photoStreamContinuation
        self.movieStreamContinuation = movieStreamContinuation
        self.previewPausedHolder = BoolHolder(false)
        #if os(iOS)
        self.selectedLensIndexHolder = IntHolder(0)
        #endif
        self.movieFileOutputHolder = MovieOutputHolder()
        self.captureModeHolder = CaptureModeHolder(captureMode)
        self.stateHandlerHolder = StateHandlerHolder(stateHandler)

        // Initial preset - refined during wireSession based on capture mode.
        // The triple camera is included so multi-lens devices get the richest
        // back camera; at zoom factor 1.0 its primary lens matches the
        // standalone wide-angle camera.
        let initialDeviceTypes: [AVCaptureDevice.DeviceType] = {
            #if os(iOS)
            return [
                .builtInTripleCamera,
                .builtInTrueDepthCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera,
            ]
            #elseif os(macOS)
            if #available(macOS 14.0, *) {
                return [.external, .builtInWideAngleCamera]
            }
            return [.builtInWideAngleCamera]
            #endif
        }()

        // Prefer a device at the configured position; fall back to any device
        // (the discovery order, which surfaces the front camera first on some
        // iPhones), then the system default.
        let initialDevice =
            AVCaptureDevice.DiscoverySession(
                deviceTypes: initialDeviceTypes,
                mediaType: .video,
                position: configuration.initialCameraPosition
            ).devices.first
            ?? AVCaptureDevice.DiscoverySession(
                deviceTypes: initialDeviceTypes,
                mediaType: .video,
                position: .unspecified
            ).devices.first
            ?? AVCaptureDevice.default(for: .video)
        self.currentDeviceHolder = DeviceHolder(initialDevice)
    }

    /// Replaces the stream continuations. Called by the facade after
    /// `cleanupCamera()` finishes the old streams so the next
    /// `initializeCamera()` works against fresh streams.
    func replacePreviewContinuation(_ continuation: AsyncStream<CIImage>.Continuation) {
        self.previewStreamContinuation = continuation
    }

    deinit {
        previewStreamContinuation?.finish()
        photoStreamContinuation?.finish()
        movieStreamContinuation?.finish()
    }

    // MARK: - Lifecycle

    func start() async -> Bool {
        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            return true
        } else {
            let success = configureCaptureSession()
            if success {
                captureSession.startRunning()
            }
            return success
        }
    }

    func stop() async {
        guard isCaptureSessionConfigured else { return }
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func cleanup() async {
        if isCaptureSessionConfigured, captureSession.isRunning {
            captureSession.stopRunning()
        }

        // Cancel notification observers and drop the cached device discovery
        // - they would otherwise accumulate / go stale across
        // re-initializations.
        notificationObservationTasks.forEach { $0.cancel() }
        notificationObservationTasks.removeAll()
        captureDevicesHolder.devices = []

        // Finish and recreate streams so the facade can re-initialize later.
        previewStreamContinuation?.finish()
        photoStreamContinuation?.finish()
        movieStreamContinuation?.finish()

        deviceInput = nil
        audioInput = nil
        photoOutput = nil
        movieFileOutput = nil
        videoOutput = nil
        videoDataOutputDelegate = nil
        isCaptureSessionConfigured = false
        coordinatorPreviewLayer = nil
        rotationCoordinator = nil
        rotationObservations.removeAll()
        activeFormatObservation?.invalidate()
        activeFormatObservation = nil

        // A stop continuation left pending by a mid-recording cleanup would
        // await forever; fail it before tearing the state down.
        if let pending = pendingRecordingContinuation {
            pendingRecordingContinuation = nil
            pending.resume(returning: .failure(.recordingFailed))
        }
        recordingDidFinish = false
        activeMovieDelegate = nil
    }

    // MARK: - Session Configuration

    /// Configures the capture session: adds the active video device input, audio input
    /// (when video mode is allowed), and the photo/video/movie outputs. Applies the
    /// per-mode session preset and `maxPhotoDimensions`, enables Bluetooth high-quality
    /// audio, and configures video stabilization on the movie output.
    @discardableResult
    private func configureCaptureSession() -> Bool {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let device = currentDevice else { return false }
        return wireSession(device: device)
    }

    /// Wires the inputs and outputs for the given capture device onto the session.
    /// Assumes the session is already inside a `beginConfiguration()` /
    /// `commitConfiguration()` block.
    private func wireSession(device: AVCaptureDevice) -> Bool {
        guard let deviceInput = try? AVCaptureDeviceInput(device: device) else {
            return false
        }

        // Apply the session preset BEFORE attaching the input and outputs.
        // A fresh session starts on the `.high` preset (16:9 formats); if
        // devices are attached first, the photo format is negotiated only
        // after the preset change settles and the first preview frames arrive
        // at the wrong aspect before snapping to 4:3.
        let captureMode = awaitCaptureMode()
        captureSession.sessionPreset = (captureMode == .photo) ? .photo : .high

        let movieFileOutput = AVCaptureMovieFileOutput()
        // By default the output writes a "movie fragment" (partial sample
        // tables) every 10 seconds, and that fragment writer is known to
        // intermittently lose the audio sample table on recordings of roughly
        // 12 seconds or longer - the file finalizes with video only and no
        // error. Disabling fragments makes the movie finalize atomically, all
        // sample tables written exactly once.
        movieFileOutput.movieFragmentInterval = .invalid
        let photoOutput = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()
        let videoDataDelegate = VideoDataOutputDelegate(
            engine: self,
            previewStreamContinuation: previewStreamContinuation
        )

        // Drop late frames instead of queueing them: the preview renders the
        // freshest frame, and stale pixel buffers are released rather than
        // piling up on the delivery queue.
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(videoDataDelegate, queue: DispatchQueue(label: "VideoDataOutputQueue"))

        guard
            captureSession.canAddInput(deviceInput),
            captureSession.canAddOutput(photoOutput),
            captureSession.canAddOutput(videoOutput),
            captureSession.canAddOutput(movieFileOutput)
        else {
            return false
        }

        captureSession.addInput(deviceInput)
        ensureAudioInputAdded()
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoOutput)
        captureSession.addOutput(movieFileOutput)

        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        self.videoOutput = videoOutput
        self.movieFileOutput = movieFileOutput
        self.videoDataOutputDelegate = videoDataDelegate

        // Install the rotation coordinator for the active device. It KVO-observes
        // the device orientation and updates `captureRotationAngle` so photo and
        // movie outputs (and the preview loop) always work with the right-way-up
        // angle - including the front camera, which is physically inverted.
        installRotationCoordinator(for: device)
        installActiveFormatObserver(for: device)

        // Session configuration:
        //  - Bluetooth high-quality audio routing (iOS 26+)
        //  - Video stabilization on the movie connection (iOS only)
        //
        // Deliberately NOT setting `photoOutput.maxPhotoDimensions` to the
        // device's largest supported still: requesting the 48MP path is only
        // meaningful paired with `.quality` prioritization, and together they
        // cost 1–3 seconds per capture. We capture at the format's default
        // resolution with `.balanced` (see dispatchPhotoCapture) so the
        // completion handler fires in a few hundred milliseconds.
        if #available(macOS 26.0, iOS 26.0, *) {
            #if os(iOS)
            captureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording = true
            #endif
        }
        #if os(iOS)
        if let movieConnection = movieFileOutput.connection(with: .video) {
            // HEVC output when supported - configured once at session
            // setup rather than per-recording, so the framing doesn't change.
            if movieFileOutput.availableVideoCodecTypes.contains(.hevc) {
                movieFileOutput.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.hevc],
                    for: movieConnection
                )
            }

            // Stabilization crops the video to leave room to correct for camera motion;
            // configuring it once (rather than per-recording) avoids changing the
            // framing at the moment recording begins.
            if movieConnection.isVideoStabilizationSupported {
                movieConnection.preferredVideoStabilizationMode = .auto
            }
        }
        #endif

        // Explicitly enable the movie output's audio connection so recordings
        // always contain an audio track.
        enableAudioConnectionOnMovieOutput()

        if #available(macOS 13.0, iOS 16.0, *) {
            // Configure the photo output's dimension ceiling from the
            // configuration. `.standard` keeps the format default (fastest);
            // `.maximum` opts into the device's largest supported still;
            // `.custom` requests explicit dimensions (clamped by the system).
            switch configuration.photoDimensions {
                case .standard:
                    break
                case .maximum:
                    photoOutput.maxPhotoDimensions =
                        device.activeFormat.supportedMaxPhotoDimensions.last ?? CMVideoDimensions(width: 0, height: 0)
                case .custom(let dimensions):
                    photoOutput.maxPhotoDimensions = dimensions
            }
        }

        if #available(macOS 13.0, *) {
            // The output's max prioritization must be at least the per-capture
            // level requested by the configuration - AVCapturePhotoOutput
            // throws `NSInvalidArgumentException`
            // ("photoQualityPrioritization must not be higher than
            // self.maxPhotoQualityPrioritization") otherwise.
            photoOutput.maxPhotoQualityPrioritization = configuration.photoQuality.avPrioritization
        }

        // Multi-lens devices open on their 1× lens.
        applyDefaultLensZoom()

        updateVideoOutputConnection()

        isCaptureSessionConfigured = true
        return true
    }

    /// Updates the session when the active capture device changes. Removes only
    /// the video inputs (preserving the audio input), adds the new device input,
    /// and reapplies `ensureAudioInputAdded`. The video data output connection
    /// is re-pinned to 0° after the configuration commits. Skipped mid-recording.
    func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }
        guard movieFileOutput?.isRecording != true else { return }

        captureSession.beginConfiguration()

        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput, deviceInput.device.hasMediaType(.video) {
                captureSession.removeInput(deviceInput)
            }
        }

        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }

        ensureAudioInputAdded()

        #if os(iOS)
        // Reset to the 1× lens (multi-lens devices) or 1.0 zoom
        // (single-lens devices) for the new device.
        applyDefaultLensZoom()
        #endif

        captureSession.commitConfiguration()

        // Re-pin the video data output connection *after* the configuration is
        // committed. Swapping the input tears down and reforms the output's
        // connections at commit time; writing the angle inside the
        // begin/commit block can hit the stale (or not-yet-reformed)
        // connection and be lost. Angle writes on a running session are
        // supported and take effect on subsequent buffers.
        updateVideoOutputConnection()
    }

    /// Switches to the next available camera. Returns whether a switch occurred.
    func switchCamera() async -> AVCaptureDevice? {
        guard movieFileOutput?.isRecording != true else { return nil }

        let devices = availableCaptureDevices()
        let next: AVCaptureDevice?
        if let active = currentDevice, let index = devices.firstIndex(of: active) {
            let nextIndex = (index + 1) % devices.count
            next = devices[nextIndex]
        } else {
            next = AVCaptureDevice.default(for: .video)
        }
        guard let next else { return nil }

        // Freeze the preview across the switch. The input swap tears down and
        // reforms every connection, and transitional buffers can briefly
        // arrive before the new device's rotation seed and the 0° re-pin of
        // the data-output connection have fully settled. The delegate reads
        // this flag per frame, so frames spanning the transition are dropped
        // and the preview freeze-cuts from the last old-camera frame straight
        // to the first correct new-camera frame. The previous pause state is
        // restored so a consumer-requested pause survives the switch.
        let previouslyPaused = previewPausedHolder.value
        previewPausedHolder.value = true
        defer { previewPausedHolder.value = previouslyPaused }

        currentDevice = next
        updateSessionForCaptureDevice(next)

        // Install a fresh rotation coordinator for the new device and apply its
        // initial capture rotation to the photo and movie output connections.
        installRotationCoordinator(for: next)
        installActiveFormatObserver(for: next)

        return next
    }

    /// Re-applies the per-mode session preset for the current capture mode.
    /// Used when the capture mode changes after the session has already been
    /// configured.
    ///
    /// Committing a new preset makes the session reconfigure the device's
    /// active format (`.photo` selects a 4:3 format, `.high` a 16:9 one), and
    /// a format change resets the zoom to the device default (the 0.5×
    /// ultra-wide on multi-lens devices). The reset frequently lands *after*
    /// `commitConfiguration()` returns, so the preview is frozen for the whole
    /// transition: the preset is committed, the retained lens is re-applied
    /// immediately (covering a format change that settles synchronously), and
    /// frames stay dropped until the format change has settled - detected via
    /// the `activeFormat` KVO generation counter - with one final lens restore
    /// (plus a short hold for the virtual device's constituent blend) before
    /// the preview resumes. The zoom reset is therefore never rendered and the
    /// selected lens is maintained across the mode switch.
    func applySessionPresetForMode(_ mode: CaptureMode) async {
        guard isCaptureSessionConfigured else { return }
        guard movieFileOutput?.isRecording != true else { return }

        let previouslyPaused = previewPausedHolder.value
        previewPausedHolder.value = true
        defer { previewPausedHolder.value = previouslyPaused }

        #if os(iOS)
        let generationBeforeCommit = formatChangeGenerationHolder.value
        #endif

        captureSession.beginConfiguration()
        captureSession.sessionPreset = (mode == .photo) ? .photo : .high
        captureSession.commitConfiguration()

        // The preset change reforms the output connections; re-pin the data
        // output's rotation, as camera switching does.
        updateVideoOutputConnection()

        #if os(iOS)
        selectLens(at: selectedLensIndexHolder.value, ramping: false)

        // Wait (frames still dropped) for the format change to land and be
        // countered by the activeFormat observer. Falls through on timeout
        // when the preset change did not select a new format (no reset).
        let settleDeadline = Date().addingTimeInterval(Self.formatSettleTimeout)
        while Date() < settleDeadline, formatChangeGenerationHolder.value == generationBeforeCommit {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        selectLens(at: selectedLensIndexHolder.value, ramping: false)

        // A format change means the lens handoff re-ran while frozen; hold a
        // moment longer so the constituent blend finishes before frames resume.
        if formatChangeGenerationHolder.value != generationBeforeCommit {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #endif
    }

    /// How long the mode-switch transition waits for a format change to land
    /// before resuming the preview.
    private static let formatSettleTimeout: TimeInterval = 0.3

    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        return try? AVCaptureDeviceInput(device: validDevice)
    }

    /// Adds the microphone input to the capture session if missing.
    private func ensureAudioInputAdded() {
        guard allowedCaptureModes.contains(.video) else { return }
        guard configuration.capturesAudio else { return }
        guard let audioDevice = audioDevice() else { return }
        guard let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else { return }
        guard !captureSession.inputs.contains(audioInput), captureSession.canAddInput(audioInput) else {
            return
        }

        captureSession.addInput(audioInput)
        self.audioInput = audioInput
        enableAudioConnectionOnMovieOutput()
    }

    func enableAudioConnectionOnMovieOutput() {
        guard let movieFileOutput,
            let audioConnection = movieFileOutput.connection(with: .audio)
        else { return }
        audioConnection.isEnabled = true
    }

    private func updateVideoOutputConnection() {
        // The video data output delivers buffers that we render into a SwiftUI
        // `Image`: the connection is pinned to 0° so raw sensor buffers arrive
        // unrotated, and rotation + mirroring are applied in the CIImage→Image
        // transform (which knows the active camera position). We intentionally
        // do NOT set `isVideoMirrored` on the connection - the front camera is
        // mirrored in the transform as well.
        //
        // This runs on every session-graph change, not just initial wiring:
        // removing and re-adding inputs (camera switch, interruption recovery)
        // recreates the output connections with the system's default rotation
        // angle, which leaves the preview rotated until the new connection is
        // re-pinned to 0°. The photo and movie connections are re-angled by
        // `applyCaptureRotationToPhotoAndMovieOutputs`; this one is the
        // counterpart for the preview pipeline.
        if #available(iOS 17.0, macOS 14.0, *) {
            videoOutput?.connection(with: .video)?.videoRotationAngle = 0
        }
    }

    // MARK: - Photo Capture

    func capturePhoto(flashMode: AVCaptureDevice.FlashMode) async -> URL? {
        guard let photoOutput else { return nil }

        // Delegate owns the continuation. No need to track state on the engine.
        return await withCheckedContinuation { continuation in
            let delegate = PhotoCaptureDelegate(
                continuation: continuation,
                photoStreamContinuation: photoStreamContinuation
            )
            dispatchPhotoCapture(
                on: photoOutput,
                flashMode: flashMode,
                delegate: delegate
            )
        }
    }

    private func dispatchPhotoCapture(
        on photoOutput: AVCapturePhotoOutput,
        flashMode: AVCaptureDevice.FlashMode,
        delegate: PhotoCaptureDelegate
    ) {
        var photoSettings = AVCapturePhotoSettings()

        // HEVC codec when supported.
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        if #available(macOS 13.0, iOS 16.0, *) {
            photoSettings.flashMode = flashMode

            // Both values mirror `CaptureConfiguration`: `.balanced` keeps the
            // ISP processing (and therefore the time to the completion
            // handler) to a few hundred milliseconds, `.quality` opts into the
            // maximum-still path; the output's dimension ceiling (standard,
            // maximum, or custom) was configured in `wireSession`.
            photoSettings.photoQualityPrioritization = configuration.photoQuality.avPrioritization
            photoSettings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

            if let photoOutputVideoConnection = photoOutput.connection(with: .video) {
                if #available(iOS 17.0, macOS 14.0, *) {
                    // Driven by the rotation coordinator - front camera gets 270°
                    // automatically, so the still comes out right-side up.
                    photoOutputVideoConnection.videoRotationAngle = captureRotationAngle
                }
            }
        }

        photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
    }

    // MARK: - Movie Recording

    func startRecordingVideo() async -> Result<Void, CameraError> {
        guard let movieFileOutput else { return .failure(.recordingFailed) }
        guard !movieFileOutput.isRecording else { return .failure(.recordingFailed) }
        guard let directoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.recordingFailed)
        }

        let fileName = UUID().uuidString
        let filePath = directoryPath.appendingPathComponent(fileName).appendingPathExtension("mp4")

        // Ensure the movie output's video connection has the rotation from the
        // rotation coordinator (correct for back/front camera and for the
        // current device orientation).
        applyCaptureRotationToPhotoAndMovieOutputs()

        enableAudioConnectionOnMovieOutput()

        // The delegate only forwards the result to the engine (weakly); all
        // recording state lives here on the actor, so the engine-side stop
        // request and the AVFoundation-side finish callback are serialized
        // without any locking.
        recordingDidFinish = false
        let delegate = MovieRecordingDelegate(engine: self)
        activeMovieDelegate = delegate

        // Whether this recording should carry audio: the movie output's audio
        // connection was just (re-)enabled and the mic input is wired. The
        // finish handler refuses to yield a file that violates this.
        recordingExpectAudioTrack =
            movieFileOutput.connection(with: .audio)?.isEnabled == true

        movieFileOutput.startRecording(to: filePath, recordingDelegate: delegate)

        playRecordingStartSound()
        return .success(())
    }

    func stopRecordingVideo() async -> Result<URL, CameraError> {
        guard let movieFileOutput, movieFileOutput.isRecording else { return .failure(.recordingFailed) }
        // A recording can finish on its own (e.g. fail on disk-full) before
        // stop is requested; the delegate has already reported it.
        guard !recordingDidFinish else { return .failure(.recordingFailed) }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<URL, CameraError>, Never>) in
            pendingRecordingContinuation = continuation
            movieFileOutput.stopRecording()
            playRecordingStopSound()
        }
    }

    /// Retains the active movie recording delegate until the recording
    /// completes, so it isn't deallocated while AVFoundation is delivering
    /// callbacks (AVCaptureMovieFileOutput only holds its delegate weakly).
    var activeMovieDelegate: MovieRecordingDelegate?

    /// The continuation installed by `stopRecordingVideo()` and resumed by
    /// `movieRecordingDidFinish(url:error:)`. Both run on this actor, which
    /// serializes the stop request against the finish callback.
    var pendingRecordingContinuation: CheckedContinuation<Result<URL, CameraError>, Never>?

    /// Set when the delegate reports the recording finished, whether or not
    /// a stop was requested - closing the window where a self-terminated
    /// recording races `stopRecordingVideo()`.
    var recordingDidFinish = false

    /// Whether the in-flight recording was started with an enabled audio
    /// connection. Set at record start; read by the finish handler.
    var recordingExpectAudioTrack = false

    /// How long the finish handler waits for the audio track to become
    /// visible in the finished file before failing the recording.
    ///
    /// With fragments disabled, a recording is final (and byte-stable) by the
    /// time this callback fires, so on the rare broken recording this timeout
    /// only delays an already-determined failure. It is kept at 10 s rather
    /// than collapsed to a single probe out of caution for OS updates
    /// reintroducing a late-flush flavor of the bug.
    private static let audioFlushTimeout: TimeInterval = 10

    /// Invoked (on the actor) by `MovieRecordingDelegate` when the recording
    /// finishes: clears the retained delegate and resumes the pending stop
    /// continuation.
    ///
    /// `AVCaptureMovieFileOutput` can deliver this callback with `error == nil`
    /// while the audio track is not (yet) visible in the file - historically
    /// caused by the periodic movie-fragment writer (disabled at wiring; see
    /// `wireSession`).
    ///
    /// Why the audio verification below is kept even though that fix is in
    /// place: the fragment bug was intermittent across iOS versions and
    /// haunted production for years before it was diagnosed (long recordings
    /// ≳12 s finalizing video-only with no error). It is unverifiable in unit
    /// tests and could resurface with an OS update; the cost of the check on
    /// a healthy recording is a single file probe, negligible next to the
    /// upload that follows. Without it, a regression would again ship mute
    /// videos silently; with it, the recording fails visibly and the user
    /// re-records.
    ///
    /// The file is probed through byte-copies on fresh temporary paths,
    /// because the in-process media cache serves a stale video-only view of
    /// the *original* path indefinitely (even through new `AVURLAsset`
    /// instances), while a copy at a never-before-seen URL is read from disk.
    /// If audio never becomes visible within the timeout, the recording fails
    /// loudly instead of handing out a silent video.
    func movieRecordingDidFinish(url: URL, error: Error?) async {
        activeMovieDelegate = nil
        recordingDidFinish = true

        // Take ownership of the continuation up front. Everything below can
        // await (the flush poll); whichever of this handler and `cleanup()`
        // claims the continuation first on this actor is its sole resumer.
        let pending = pendingRecordingContinuation
        pendingRecordingContinuation = nil

        if error != nil {
            pending?.resume(returning: .failure(.recordingFailed))
            return
        }

        if recordingExpectAudioTrack {
            let audioVisible = await waitForAudioTrack(in: url)
            if !audioVisible {
                // Guard rail: audio was wired but never landed in the file.
                // Delete the mute file and surface a visible failure so the
                // user re-records rather than posting a silent video.
                try? FileManager.default.removeItem(at: url)
                pending?.resume(returning: .failure(.recordingFailed))
                return
            }
        }

        movieStreamContinuation?.yield(url)
        pending?.resume(returning: .success(url))
    }

    /// Polls byte-copies of the recorded file until an audio track is
    /// visible, or returns `false` when the flush timeout elapses.
    ///
    /// On a healthy recording the very first probe succeeds, so the poll is
    /// free; the loop only spends time on a recording that is already broken
    /// (and will fail loudly when the caller sees `false`). See the
    /// `movieRecordingDidFinish` doc comment for why this verification is
    /// retained alongside the movie-fragment fix.
    private func waitForAudioTrack(in url: URL) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.audioFlushTimeout)
        while Date() < deadline {
            let probeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio-flush-probe-\(UUID().uuidString).mp4")
            do {
                // Force a real read of the bytes: the in-process cache will
                // happily serve the stale video-only view of `url` itself.
                let bytes = try Data(contentsOf: url)
                try bytes.write(to: probeURL)

                let probeAsset = AVURLAsset(url: probeURL)
                let audioTrackCount: Int
                if #available(iOS 15.0, macOS 12.0, *) {
                    audioTrackCount = (try? await probeAsset.loadTracks(withMediaType: .audio).count) ?? 0
                } else {
                    audioTrackCount = probeAsset.tracks(withMediaType: .audio).count
                }
                try? FileManager.default.removeItem(at: probeURL)

                if audioTrackCount > 0 {
                    return true
                }
            } catch {
                // Probe failed (e.g. transient read error); retry on the next
                // tick below.
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    // MARK: - Recovery

    /// Re-adds the active video input and the audio input if either is missing,
    /// re-enables the movie output's audio connection, and ensures the session
    /// is running again.
    func restoreSessionInputs() {
        guard isCaptureSessionConfigured else { return }
        guard movieFileOutput?.isRecording != true else { return }

        captureSession.beginConfiguration()

        let hasVideoInput = captureSession.inputs.contains { input in
            guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
            return deviceInput.device.hasMediaType(.video)
        }
        if !hasVideoInput, let device = currentDevice,
            let deviceInput = deviceInputFor(device: device),
            !captureSession.inputs.contains(deviceInput),
            captureSession.canAddInput(deviceInput)
        {
            captureSession.addInput(deviceInput)
            self.deviceInput = deviceInput
        }

        ensureAudioInputAdded()
        enableAudioConnectionOnMovieOutput()

        captureSession.commitConfiguration()

        // Re-pin after commit - see updateSessionForCaptureDevice.
        updateVideoOutputConnection()

        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    /// Tears down and rebuilds the capture session after a media-services reset.
    @discardableResult
    func rebuildCaptureSession() -> Bool {
        guard movieFileOutput?.isRecording != true else { return false }
        guard let device = currentDevice else { return false }

        captureSession.beginConfiguration()
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        captureSession.commitConfiguration()

        deviceInput = nil
        audioInput = nil
        photoOutput = nil
        movieFileOutput = nil
        videoOutput = nil
        videoDataOutputDelegate = nil
        isCaptureSessionConfigured = false
        coordinatorPreviewLayer = nil
        rotationCoordinator = nil
        rotationObservations.removeAll()
        captureDevicesHolder.devices = []

        captureSession.beginConfiguration()
        let success = wireSession(device: device)
        captureSession.commitConfiguration()

        if success {
            captureSession.startRunning()
        }
        return success
    }

    // MARK: - Notification Observers

    /// Notification observation tasks. The notification streams never finish
    /// on their own and `initializeCamera()` can run more than once, so the
    /// tasks are retained here and cancelled in `cleanup()` - otherwise every
    /// initialization would leak three live tasks.
    var notificationObservationTasks: [Task<Void, Never>] = []

    func startObservingNotifications() async {
        guard #available(macOS 12.0, iOS 15.0, *) else { return }

        // Cancel observers from a previous initialization before re-subscribing.
        notificationObservationTasks.forEach { $0.cancel() }
        notificationObservationTasks.removeAll()

        let session = captureSession

        notificationObservationTasks.append(
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVCaptureSession.wasInterruptedNotification, object: session)
                {
                    guard let self else { return }
                    await self.handleWasInterrupted()
                }
            })
        notificationObservationTasks.append(
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: AVCaptureSession.interruptionEndedNotification, object: session)
                {
                    guard let self else { return }
                    await self.handleInterruptionEnded()
                }
            })
        notificationObservationTasks.append(
            Task { [weak self] in
                for await note in NotificationCenter.default.notifications(
                    named: AVCaptureSession.runtimeErrorNotification, object: session)
                {
                    guard let self else { return }
                    await self.handleRuntimeError(note)
                }
            })
    }

    private func handleWasInterrupted() async {
        await MainActor.run { [stateHandler] in
            stateHandler?.didInterrupt()
        }
    }

    private func handleInterruptionEnded() async {
        restoreSessionInputs()
        await MainActor.run { [stateHandler] in
            stateHandler?.didEndInterruption()
        }
    }

    private func handleRuntimeError(_ note: Notification) async {
        guard #available(macOS 12.0, iOS 15.0, *) else { return }
        guard let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        switch error.code {
            #if os(iOS)
                case .deviceNotConnected:
                    // Re-query the hardware: the cache may still contain the
                    // device that just disconnected.
                    captureDevicesHolder.devices = []
                    if let active = currentDevice,
                        !availableCaptureDevices().contains(active),
                        let fallback = availableCaptureDevices().first
                    {
                        currentDevice = fallback
                    }
                    restoreSessionInputs()
                    await MainActor.run { [stateHandler] in
                        stateHandler?.didFail(.deviceNotAvailable)
                    }

                case .mediaServicesWereReset:
                    // If a recording is in flight, the recording delegate already
                    // reports the failure. Skip the rebuild and surface the error.
                    guard movieFileOutput?.isRecording != true else {
                        await MainActor.run { [stateHandler] in
                            stateHandler?.didFail(
                                .unknown("Camera system was reset. Please reopen the camera.")
                            )
                        }
                        return
                    }
                    let rebuilt = rebuildCaptureSession()
                    if !rebuilt {
                        await MainActor.run { [stateHandler] in
                            stateHandler?.didFail(
                                .unknown("Camera system was reset. Please reopen the camera.")
                            )
                        }
                    }
            #endif

            default:
                break
        }
    }

    // MARK: - Preview Pause

    /// Preview-pause flag. Set by the facade via `setPreviewPaused(_:)` and
    /// read by `VideoDataOutputDelegate` on every frame. Stored as a
    /// reference type so the delegate (running on AVFoundation's private
    /// queue) can read it without an actor hop. Reads/writes are word-sized;
    /// tearing is harmless (the worst case is one extra frame yielded or
    /// skipped).
    let previewPausedHolder: BoolHolder

    final class BoolHolder: @unchecked Sendable {
        var value: Bool
        init(_ value: Bool) { self.value = value }
    }

    func setPreviewPaused(_ paused: Bool) {
        previewPausedHolder.value = paused
    }

    nonisolated func isPreviewPausedNow() -> Bool {
        previewPausedHolder.value
    }

    // MARK: - Lens Selection
    //
    // Multi-lens (virtual) devices are an iOS concept; on macOS every camera
    // reports a single lens and switching is a no-op.

    #if os(iOS)
    /// The index of the currently selected lens on the active device. Stored
    /// as a reference type so `nonisolated` snapshots can read it without an
    /// actor hop. Only meaningful on multi-lens (virtual) devices.
    let selectedLensIndexHolder: IntHolder

    final class IntHolder: @unchecked Sendable {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    /// Counts `activeFormat` changes on the active device. The mode-switch
    /// preset transition (see `applySessionPresetForMode`) uses it to detect
    /// that the format change - and its zoom reset - has landed.
    let formatChangeGenerationHolder = IntHolder(0)

    /// The number of lenses available on the active camera. Non-virtual
    /// devices report a single lens.
    nonisolated func lensCountSnapshot() -> Int {
        guard let device = currentDeviceHolder.device else { return 1 }
        let lenses = device.constituentDevices
        return lenses.count > 1 ? lenses.count : 1
    }

    nonisolated func selectedLensIndexSnapshot() -> Int {
        selectedLensIndexHolder.value
    }

    /// The display magnification of each lens on the active device, relative
    /// to the wide lens - e.g. `[0.5, 1, 3]` for a triple camera.
    ///
    /// Derived from the virtual device's switchover zoom factors: each factor
    /// encodes the focal ratio between adjacent constituents, so the ratios
    /// between factors (anchored at the 1× wide lens) yield the magnifications
    /// without assuming any particular zoom-factor unit convention.
    nonisolated func lensMagnificationsSnapshot() -> [CGFloat] {
        guard let device = currentDeviceHolder.device else { return [] }
        let lenses = device.constituentDevices
        guard lenses.count > 1 else { return [] }
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors

        let firstIsUltraWide = lenses.first?.deviceType == .builtInUltraWideCamera
        let firstFactor: CGFloat = firstIsUltraWide ? 0.5 : 1.0
        var factors: [CGFloat] = [firstFactor]
        guard let firstSwitchOver = switchOvers.first, firstSwitchOver.doubleValue != 0 else {
            return factors
        }

        // The wide lens is the second constituent and is the 1× anchor; every
        // subsequent factor scales from its switchover point.
        for index in 1..<lenses.count {
            factors.append(CGFloat(truncating: switchOvers[index - 1]) / CGFloat(truncating: firstSwitchOver))
        }
        return factors
    }

    /// Selects the lens at `index` on the active multi-lens (virtual) device,
    /// gliding the zoom smoothly to the target.
    ///
    /// A virtual device routes capture to a constituent lens automatically
    /// based on `videoZoomFactor`: the widest lens sits at the device's
    /// minimum zoom factor, and each subsequent lens's native magnification
    /// sits at its switchover point (`virtualDeviceSwitchOverVideoZoomFactors`
    /// has one element per constituent after the first). The zoom factor is
    /// aimed a small epsilon past that point - landing exactly on the
    /// switchover makes the lens handoff stall mid-transition before the
    /// zoom continues to the target.
    ///
    /// - Parameters:
    ///   - index: Position of the lens, in `0 ..< lensCountSnapshot()`.
    ///   - ramping: When `true` (user-initiated changes on a running
    ///     session), the zoom glides to the target at `lensRampRate` instead
    ///     of snapping. When `false` (session wiring, camera switches - where
    ///     the device may not be running yet) the zoom is set directly.
    func selectLens(at index: Int, ramping: Bool) {
        guard let device = currentDeviceHolder.device else { return }
        guard let targetZoom = nativeZoomFactor(forLensAt: index) else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if ramping {
                device.ramp(toVideoZoomFactor: targetZoom, withRate: Float(Self.lensRampRate))
            } else {
                device.videoZoomFactor = targetZoom
            }
            selectedLensIndexHolder.value = index
        } catch {
            // Lens change failed - continue silently.
        }
    }

    /// Selects the lens at `index`, gliding the zoom smoothly to the target.
    func selectLens(at index: Int) {
        selectLens(at: index, ramping: true)
    }

    /// The zoom factor at which the lens at `index` natively sits, or `nil`
    /// when the index is invalid for the active device.
    private func nativeZoomFactor(forLensAt index: Int) -> CGFloat? {
        guard let device = currentDeviceHolder.device else { return nil }
        let lenses = device.constituentDevices
        guard lenses.count > 1, lenses.indices.contains(index) else { return nil }

        if index == 0 {
            return device.minAvailableVideoZoomFactor
        }
        let switchOverIndex = index - 1
        guard switchOverIndex < device.virtualDeviceSwitchOverVideoZoomFactors.count else { return nil }
        let switchOverZoomFactor = CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[switchOverIndex])
        return switchOverZoomFactor + Self.lensSelectionEpsilon
    }

    /// Distance past the switchover point used when engaging a lens: large
    /// enough to firmly hand off to the target constituent, small enough that
    /// the field of view still matches the lens's advertised magnification.
    private static let lensSelectionEpsilon: CGFloat = 0.05

    /// Ramp speed for smooth lens transitions, in zoom-factor units per
    /// second. A 0.5× ↔ 1× hop therefore completes in a few hundredths of a
    /// second - quick enough to read as an immediate lens change.
    private static let lensRampRate: CGFloat = 20

    /// Cycles to the next lens of the active multi-lens (virtual) device.
    func selectNextLens() {
        let count = lensCountSnapshot()
        guard count > 1 else { return }
        selectLens(at: (selectedLensIndexHolder.value + 1) % count, ramping: true)
    }

    /// Applies the default zoom for the active device: the 1× lens on
    /// multi-lens devices, no zoom otherwise.
    private func applyDefaultLensZoom() {
        guard let device = currentDeviceHolder.device else { return }

        if let oneXIndex = lensMagnificationsSnapshot().firstIndex(where: { $0 == 1.0 }) {
            // Direct set - at session wiring time the device may not be
            // running yet, so a zoom ramp would not progress.
            selectLens(at: oneXIndex, ramping: false)
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.videoZoomFactor != 1.0 {
                device.videoZoomFactor = 1.0
            }
        } catch {
            // Zoom change failed - continue silently.
        }
    }
    #else
    nonisolated func lensCountSnapshot() -> Int { 1 }

    nonisolated func selectedLensIndexSnapshot() -> Int { 0 }

    nonisolated func lensMagnificationsSnapshot() -> [CGFloat] { [] }

    func selectLens(at index: Int) {}

    func selectNextLens() {}

    private func applyDefaultLensZoom() {}
    #endif

    // MARK: - Torch

    /// Applies the torch immediately when in video mode. No-op in photo mode
    /// or when the current device doesn't have a torch.
    func applyTorchImmediately(mode: AVCaptureDevice.FlashMode) {
        guard captureModeHolder.mode == .video,
            let device = currentDeviceHolder.device,
            device.isTorchAvailable
        else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            switch mode {
                case .off: if device.torchMode != .off { device.torchMode = .off }
                case .on: device.torchMode = .on
                case .auto: device.torchMode = .auto
                @unknown default: device.torchMode = .off
            }
        } catch {
            // Torch update failed - continue silently.
        }
    }

    // MARK: - Rotation

    /// Returns the rotation angle to apply to recording-style connections (photo
    /// and movie outputs) for the current capture device.
    ///
    /// Reads `captureRotationAngle` from the rotation coordinator (set when
    /// `installRotationCoordinator(for:)` runs and updated automatically when
    /// device orientation changes) and applies it to the photo and movie
    /// output connections. With this in place, the front camera no longer
    /// produces rotated videos and the recording follows the device's gravity.
    func applyCaptureRotationToPhotoAndMovieOutputs() {
        guard #available(macOS 14.0, iOS 17.0, *) else { return }
        let angle = captureRotationAngle
        if let connection = photoOutput?.connection(with: .video) {
            connection.videoRotationAngle = angle
        }
        if let connection = movieFileOutput?.connection(with: .video) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: - System Sounds

    func playRecordingStartSound() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1113)
        #endif
    }

    func playRecordingStopSound() {
        #if os(iOS)
        AudioServicesPlaySystemSound(1114)
        #endif
    }

    // MARK: - Snapshots for the facade

    nonisolated func isRunningSnapshot() -> Bool {
        captureSession.isRunning
    }

    nonisolated func currentDeviceSnapshot() -> AVCaptureDevice? {
        currentDeviceHolder.device
    }

    nonisolated func isRecordingSnapshot() -> Bool {
        movieFileOutputHolder.output?.isRecording ?? false
    }

    nonisolated func recordedDurationSecondsSnapshot() -> Double {
        movieFileOutputHolder.output?.recordedDuration.seconds ?? 0
    }

    /// Reports the engine's intended capture mode. The facade passes this
    /// in via `awaitCaptureMode()` and the engine also stores it for
    /// session-preset decisions. Backed by `captureModeHolder` so `nonisolated`
    /// reads work.
    var captureMode: CaptureMode {
        get { captureModeHolder.mode }
        set { captureModeHolder.mode = newValue }
    }

    func setCaptureModeForWiring(_ mode: CaptureMode) {
        captureModeHolder.mode = mode
    }

    /// Returns the currently-set capture mode for the engine's session
    /// wiring. Should be set by the facade before `start()` is called.
    nonisolated func awaitCaptureMode() -> CaptureMode {
        captureModeHolder.mode
    }

    nonisolated func isUsingFrontCaptureDeviceNow() -> Bool {
        guard let device = currentDeviceHolder.device else { return false }
        return frontCaptureDevices().contains(device)
    }

    nonisolated func isUsingBackCaptureDeviceNow() -> Bool {
        guard let device = currentDeviceHolder.device else { return false }
        return backCaptureDevices().contains(device)
    }

    nonisolated func isFlashAvailableNow() -> Bool {
        currentDeviceHolder.device?.isFlashAvailable ?? false
    }

    nonisolated func isTorchAvailableNow() -> Bool {
        currentDeviceHolder.device?.isTorchAvailable ?? false
    }

    /// Cached result of device discovery. `DiscoverySession` is expensive,
    /// and the facade's availability checks run on every SwiftUI evaluation,
    /// so discovery results are cached and refreshed when the engine
    /// (re)configures or cleans up. Concurrent first access may both compute
    /// the list; the writes are idempotent and equivalent.
    let captureDevicesHolder = DeviceListHolder()

    final class DeviceListHolder: @unchecked Sendable {
        var devices: [AVCaptureDevice] = []
    }

    nonisolated func availableCaptureDevices() -> [AVCaptureDevice] {
        if captureDevicesHolder.devices.isEmpty {
            captureDevicesHolder.devices = captureDevicesFiltered()
        }
        return captureDevicesHolder.devices
    }

    private nonisolated var defaultDeviceTypes: [AVCaptureDevice.DeviceType] {
        #if os(iOS)
        return [
            .builtInTripleCamera,
            .builtInTrueDepthCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
        ]
        #elseif os(macOS)
        // See `initialDeviceTypes`: `.external` adds external webcams and
        // Continuity Camera devices on macOS 14+.
        if #available(macOS 14.0, *) {
            return [.external, .builtInWideAngleCamera]
        }
        return [.builtInWideAngleCamera]
        #endif
    }

    private nonisolated func allCaptureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: defaultDeviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    private nonisolated func frontCaptureDevices() -> [AVCaptureDevice] {
        allCaptureDevices().filter { $0.position == .front }
    }

    private nonisolated func backCaptureDevices() -> [AVCaptureDevice] {
        allCaptureDevices().filter { $0.position == .back }
    }

    private nonisolated func captureDevicesFiltered() -> [AVCaptureDevice] {
        var devices = [AVCaptureDevice]()
        #if os(iOS)
        // Prefer the back device with the most constituent lenses (the triple
        // camera on Pro models) so multi-lens switching is available. At zoom
        // factor 1.0 a virtual device's primary lens matches the standalone
        // wide-angle camera, so framing is unchanged.
        let sortedBackDevices = backCaptureDevices().sorted { device1, device2 in
            device1.constituentDevices.count > device2.constituentDevices.count
        }
        if let backDevice = sortedBackDevices.first {
            devices += [backDevice]
        }
        #else
        // macOS: the discovery session is already video-only, and camera
        // position is unreliable there - the built-in FaceTime camera reports
        // `.unspecified` (verified) while external cameras may report `.back`
        // - so keep every discovered device rather than filtering by position.
        devices += allCaptureDevices()
        #endif
        if let frontDevice = frontCaptureDevices().first, !devices.contains(frontDevice) {
            devices += [frontDevice]
        }

        if #available(iOS 14.0, *) {
            return devices.filter { $0.isConnected && !$0.isSuspended }
        } else {
            return devices.filter { $0.isConnected }
        }
    }

    private nonisolated func audioDevice() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio)
    }
}

/// State-update forwarding closure installed by the facade. Called from the
/// engine on `MainActor` to update `@Published` properties on `CameraService`.
@available(iOS 13.0, macOS 10.15, *)
@MainActor
final class CameraEngineStateHandler {
    let didInterrupt: () -> Void
    let didEndInterruption: () -> Void
    let didFail: (CameraError) -> Void

    init(
        didInterrupt: @escaping () -> Void,
        didEndInterruption: @escaping () -> Void,
        didFail: @escaping (CameraError) -> Void
    ) {
        self.didInterrupt = didInterrupt
        self.didEndInterruption = didEndInterruption
        self.didFail = didFail
    }
}

// MARK: - Configuration Mapping

/// Maps the configuration's photo quality to AVFoundation's prioritization.
/// The AVFoundation type requires iOS 13 / macOS 13, which is why
/// `CaptureConfiguration` exposes its own enum.
@available(iOS 13.0, macOS 13.0, *)
extension CaptureConfiguration.PhotoQuality {
    fileprivate var avPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
            case .balanced: return .balanced
            case .quality: return .quality
        }
    }
}
