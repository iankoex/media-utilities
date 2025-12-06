//
//  CaptureMode.swift
//  MediaUtilities
//
//  Created by ian on 06/12/2025.
//

// MARK: - Capture Mode

/// Supported capture modes for the camera interface.
///
/// `CaptureMode` defines whether the camera interface is currently
/// configured for photo capture or video recording. This enum
/// is used to switch between different capture functionalities
/// and update the UI accordingly.
public enum CaptureMode: String, CaseIterable {
    /// Photo capture mode for taking still images.
    case photo = "photo"

    /// Video recording mode for capturing video footage.
    case video = "video"

    /// The system image name representing this capture mode.
    ///
    /// This property provides the appropriate SF Symbol for UI display
    /// based on the current capture mode.
    ///
    /// - Returns: A string containing the SF Symbol name.
    var systemImage: String {
        switch self {
            case .photo:
                return "camera"
            case .video:
                return "video"
        }
    }
}
