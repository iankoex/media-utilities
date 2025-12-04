//
//  MediaUtilitiesError.swift
//  MediaUtilities
//
//  Created by Ian on 08/12/2022.
//

import Foundation

// MARK: - Media Utilities Error

/// Errors that can occur during media processing operations.
///
/// `MediaUtilitiesError` encompasses all possible failure scenarios when working
/// with media utilities, including image processing, file operations, and drop operations.
/// Each error provides a localized description for user-facing error messages.
enum MediaUtilitiesError: LocalizedError {
    /// The operation was cancelled by the user.
    case cancelled

    /// The image data is nil or invalid.
    case nilImage

    /// The drop operation is blocked because the delegate is guarded.
    case isGuarded

    /// The dropped item does not conform to the required type identifiers.
    case lacksConformingTypeIdentifiers

    /// The dropped item is not audiovisual content and cannot be played.
    case lacksAudioVisualContent

    /// Failed to create a valid image from the provided data.
    case badImage

    /// Failed to retrieve an image from the specified URL.
    ///
    /// On macOS, this may indicate insufficient permissions to access the URL.
    case failedToGetImageFromURL

    /// An error occurred during image import with a custom description.
    case importImageError(String)

    /// An error occurred during image cropping with a custom description.
    case cropImageError(String)

    /// An error occurred during image rotation with a custom description.
    case rotateImageError(String)

    /// An error occurred during image straightening with a custom description.
    case straightenImageError(String)
    
    public var errorDescription: String? {
        let base = "The operation could not be completed. "
        switch self {
            case .cancelled:
                return base + "operation was cancelled"
            case .nilImage:
                return base + "Image is nil, for one reason or another"
            case .isGuarded:
                return base + "The DropDelegate is guarded"
            case .lacksConformingTypeIdentifiers:
                return base + "The Drop Item Does Not Conform to The Type Identifiers Provided"
            case .lacksAudioVisualContent:
                return base + "The Drop Item is Not an AudioVisual Content, it is not playable"
            case .badImage:
                return base + "Failed to get Image from data"
            case .failedToGetImageFromURL:
                return base + "Failed to get Image from URL, if on macOS, ensure you have the correct permissions"
            case .importImageError(let str):
                return base + "Image Import Error: \(str)"
            case .cropImageError(let str):
                return base + "Failed to Crop Image: \(str)"
            case .rotateImageError(let str):
                return base + "Failed to Rotate Image: \(str)"
            case .straightenImageError(let str):
                return base + "Failed to Straighten Image: \(str)"
        }
    }
}
