//
//  CameraService+Capture.swift
//  MediaUtilities
//
//  Created by ian on 12/03/2025.
//

import AVFoundation
import Foundation

// MARK: - Capture Operations

/// Capture lifecycle and device-control operations for `CameraService`.
///
/// This extension groups the service's capture operations: starting and
/// stopping the capture session, switching cameras and lenses, and the
/// low-level video-recording controls. (Photo capture and the high-level
/// recording intents with permission handling live in
/// `CameraService+Intents.swift`.) Every operation forwards to the internal
/// `CameraEngine` actor, which serializes all AVFoundation work; results are
/// delivered through `async` returns and `Result` values.
///
/// ## Usage
///
/// ```swift
/// // Start the session, then record a video clip
/// guard await cameraService.start() else { return }
/// if case .success = await cameraService.startVideoRecording() {
///     let video = await cameraService.stopVideoRecording()
/// }
/// ```
@available(iOS 13.0, macOS 10.15, *)
extension CameraService {

    /// Starts the camera capture session.
    ///
    /// On first use the session is configured (device input, outputs, and the
    /// session preset for the active `CaptureMode`); afterwards this simply
    /// resumes the flow of frames to the preview pipeline and the photo and
    /// movie outputs.
    ///
    /// - Returns: `true` if the session is running; `false` if camera
    ///   authorization was denied or session configuration failed.
    public func start() async -> Bool {
        guard authorizationStatus == .authorized else { return false }
        return await engine.start()
    }

    /// Stops the camera capture session and halts preview frame streaming.
    ///
    /// The session configuration is preserved - call `start()` to resume
    /// without reconfiguring.
    public func stop() async {
        await engine.stop()
    }

    /// Switches between available front and back cameras.
    ///
    /// The preview briefly freezes across the switch so transitional frames
    /// never appear, and the lens state (`lensCount`, `selectedLensIndex`,
    /// `lensMagnifications`) is refreshed for the newly active device.
    ///
    /// - Note: Skipped while a video recording is in progress.
    public func switchCamera() async {
        _ = await engine.switchCamera()

        // The two cameras' sensors are mounted 180° apart, so the preview
        // rotation changes with the active camera even though the device
        // orientation did not.
        syncRotationFromDevice()

        // The active device (and therefore its lens state) may have changed.
        lensCount = engine.lensCountSnapshot()
        lensMagnifications = engine.lensMagnificationsSnapshot()
        selectedLensIndex = engine.selectedLensIndexSnapshot()
    }

    /// Cycles to the next available lens on the active camera.
    ///
    /// Lenses advance in ascending magnification order - 1× → 2× → 3× → 0.5×
    /// → 1× - looping back around after the longest lens.
    ///
    /// - Note: Only multi-lens (virtual) devices support lens switching; on
    ///   single-lens devices this is a no-op.
    public func switchLens() async {
        await engine.selectNextLens()
        selectedLensIndex = engine.selectedLensIndexSnapshot()
    }

    /// Selects the lens at `index` on the active camera.
    ///
    /// - Parameter index: Position of the lens in `lensMagnifications`.
    /// - Note: No-op when the index is out of range or the device has a
    ///   single lens.
    public func selectLens(at index: Int) async {
        await engine.selectLens(at: index)
        selectedLensIndex = engine.selectedLensIndexSnapshot()
    }

    /// Starts recording video to a temporary file.
    ///
    /// The recording continues until `stopRecordingVideo()` is called. Use
    /// `movieFileStream` to receive the URL when recording completes.
    ///
    /// - Returns: `.success` when recording begins; `.failure(.permissionDenied)`
    ///   or `.failure(.microphonePermissionDenied)` without authorization,
    ///   `.failure(.deviceNotAvailable)` without a camera, or
    ///   `.failure(.recordingFailed)` if the recorder could not start.
    public func startRecordingVideo() async -> Result<Void, CameraError> {
        await engine.startRecordingVideo()
    }

    /// Stops video recording and finalizes the output file.
    ///
    /// - Returns: `.success` with the file URL, or `.failure(.recordingFailed)`
    ///   if no recording was in progress or finalization failed.
    public func stopRecordingVideo() async -> Result<URL, CameraError> {
        await engine.stopRecordingVideo()
    }

    /// Toggles through the available flash modes: off → on → auto → off.
    ///
    /// In photo mode the setting applies to the next still. In video mode the
    /// torch is applied immediately, mirroring the system camera behavior.
    public func toggleFlashMode() async {
        let mode = flashMode
        let next: AVCaptureDevice.FlashMode
        switch mode {
            case .off: next = .on
            case .on: next = .auto
            default: next = .off
        }
        flashMode = next
    }
}
