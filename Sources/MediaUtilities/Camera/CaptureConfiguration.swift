//
//  CaptureConfiguration.swift
//  MediaUtilities
//
//  Created by ian on 27/08/2026.
//

import AVFoundation
import CoreMedia

// MARK: - Capture Configuration

/// A declarative description of how the camera interface should behave.
///
/// `CaptureConfiguration` bundles every customization point of the camera
/// pipeline into a single value that is passed to `CameraCaptureView`,
/// `CameraService`, or the `.cameraCapture` view modifier. Defaults reproduce
/// the library's standard behavior: photo + video modes, fast `.balanced`
/// stills at the format's default resolution, back camera first, with audio.
///
/// ## Usage
///
/// ```swift
/// var configuration = CaptureConfiguration()
/// configuration.allowedCaptureModes = [.photo]
/// configuration.photoQuality = .quality
/// configuration.photoDimensions = .maximum
///
/// CameraCaptureView(configuration: configuration) { result in
///     switch result {
///     case .success(let url):
///         print("Media saved to: \(url)")
///     case .failure(let error):
///         print("Capture failed: \(error)")
///     }
/// }
/// ```
///
/// ## Quality and Resolution Trade-offs
///
/// `.balanced` stills at the standard resolution capture in a few hundred
/// milliseconds. Requesting `.quality` and/or `.maximum` dimensions opts into
/// the device's "maximum still" path (48MP on modern iPhones), which produces
/// the best photographs but takes 1–3 seconds per capture. Apple recommends
/// pairing `.maximum` with `.quality`.
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
@available(iOS 13.0, macOS 10.15, *)
public struct CaptureConfiguration: Equatable, Sendable {

    // MARK: Capture Modes

    /// The capture modes that should be available in the camera interface.
    ///
    /// Defaults to `[.photo, .video]` to allow both photo and video capture.
    /// Use `[.photo]` to restrict to photo-only or `[.video]` for video-only.
    public var allowedCaptureModes: Set<CaptureMode>

    // MARK: Photo Capture

    /// The image signal processing level requested for still captures.
    ///
    /// `.balanced` (the default) keeps capture latency low - the completion
    /// handler fires in a few hundred milliseconds. `.quality` requests the
    /// maximum processing pipeline for the best stills at the cost of a
    /// noticeably longer capture (1–3 seconds).
    public var photoQuality: PhotoQuality

    /// The resolution requested for still captures.
    public var photoDimensions: PhotoDimensions

    // MARK: Device Selection

    /// The camera position that is active when the interface first opens.
    ///
    /// Defaults to `.back`. Users can still switch cameras in the interface.
    public var initialCameraPosition: AVCaptureDevice.Position

    // MARK: Lens Selection UI

    /// Whether the camera interface shows the lens switcher — the button that
    /// cycles the active lens on multi-lens (virtual) devices (1× → 2× → 3× →
    /// 0.5× → 1×).
    ///
    /// Defaults to `false`, keeping the interface to a single 1× lens.
    /// Programmatic lens selection (`CameraService.selectLens(at:)` and
    /// `switchLens()`) remains available regardless of this setting.
    public var showsLensSwitcher: Bool

    // MARK: Audio

    /// Whether the microphone input is added to the capture session in video
    /// mode. When `false`, recordings contain no audio track.
    public var capturesAudio: Bool

    // MARK: - Initialization

    /// Creates a capture configuration.
    ///
    /// - Parameters:
    ///   - allowedCaptureModes: Capture modes available in the interface.
    ///     Defaults to `[.photo, .video]`.
    ///   - photoQuality: Image signal processing level for stills.
    ///     Defaults to `.balanced`.
    ///   - photoDimensions: Still resolution. Defaults to `.standard`.
    ///   - initialCameraPosition: Camera active on first open.
    ///     Defaults to `.back`.
    ///   - showsLensSwitcher: Whether the interface shows the lens switcher
    ///     button. Defaults to `false`.
    ///   - capturesAudio: Whether video mode includes the microphone.
    ///     Defaults to `true`.
    public init(
        allowedCaptureModes: Set<CaptureMode> = [.photo, .video],
        photoQuality: PhotoQuality = .balanced,
        photoDimensions: PhotoDimensions = .standard,
        initialCameraPosition: AVCaptureDevice.Position = .back,
        showsLensSwitcher: Bool = false,
        capturesAudio: Bool = true
    ) {
        self.allowedCaptureModes = allowedCaptureModes
        self.photoQuality = photoQuality
        self.photoDimensions = photoDimensions
        self.initialCameraPosition = initialCameraPosition
        self.showsLensSwitcher = showsLensSwitcher
        self.capturesAudio = capturesAudio
    }
}

// MARK: - Photo Quality

@available(iOS 13.0, macOS 10.15, *)
extension CaptureConfiguration {

    /// The image signal processing level requested for still captures.
    ///
    /// Mirrors `AVCapturePhotoOutput.QualityPrioritization` without exposing
    /// its availability restrictions on the configuration itself.
    public enum PhotoQuality: Equatable, Sendable {
        /// Fast processing - captures complete in a few hundred milliseconds.
        case balanced

        /// Maximum processing - the best stills, taking 1–3 seconds each.
        case quality
    }
}

// MARK: - Photo Dimensions

@available(iOS 13.0, macOS 10.15, *)
extension CaptureConfiguration {

    /// The resolution requested for still captures.
    ///
    /// - `standard`: The active format's default photo resolution (fastest).
    /// - `maximum`: The device's largest supported still - 48MP on modern
    ///   iPhones. Requires significant processing; pair with
    ///   `photoQuality: .quality` per Apple's guidance.
    /// - `custom`: An explicit `CMVideoDimensions` request. Dimensions the
    ///   device cannot produce are clamped by the system.
    public enum PhotoDimensions: Equatable, Sendable {
        case standard
        case maximum
        case custom(CMVideoDimensions)

        public static func == (lhs: PhotoDimensions, rhs: PhotoDimensions) -> Bool {
            switch (lhs, rhs) {
                case (.standard, .standard): return true
                case (.maximum, .maximum): return true
                case (.custom(let lhsDimensions), .custom(let rhsDimensions)):
                    return lhsDimensions.width == rhsDimensions.width
                        && lhsDimensions.height == rhsDimensions.height
                default: return false
            }
        }
    }
}
