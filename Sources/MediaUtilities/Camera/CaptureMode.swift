//
//  CaptureMode.swift
//  MediaUtilities
//
//  Created by ian on 06/12/2025.
//

import Foundation

// MARK: - Capture Mode

/// Supported capture modes for the camera interface.
///
/// `CaptureMode` defines whether the camera interface is currently
/// configured for photo capture or video recording. This enum
/// is used to switch between different capture functionalities
/// and update the UI accordingly.
///
/// ## Usage
///
/// ```swift
/// var configuration = CaptureConfiguration()
/// configuration.allowedCaptureModes = [.photo, .video]
/// ```
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
public enum CaptureMode: String, CaseIterable, Identifiable, Sendable {
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

    public var id: String {
        self.rawValue
    }
}
