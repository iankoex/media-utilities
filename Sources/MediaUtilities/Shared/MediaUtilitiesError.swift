//
//  MediaUtilitiesError.swift
//  
//
//  Created by Ian on 08/12/2022.
//

import Foundation

enum MediaUtilitiesError: LocalizedError {
    case isGuarded
    case lacksConformingTypeIdentifiers
    case lacksAudioVisualContent
    case badImage
    case failedToGetImageFromURL
    case importImageError(String)
    case failedToGetImageWithCorrectOrientation
    case failedToGetCGImageFromUnifiedImage
    case failedToCropCGImage
    case failedToCropImageIntoACircle
    
    public var errorDescription: String? {
        let base = "The operation could not be completed. "
        switch self {
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
            case .failedToGetImageWithCorrectOrientation:
                return base + "Failed to get Image with Correct Orientation"
            case .failedToGetCGImageFromUnifiedImage:
                return base + "Failed to get CGImage from Unified Image"
            case .failedToCropCGImage:
                return base + "Failed to crop CGImage"
            case .failedToCropImageIntoACircle:
                return base + "Failed to crop Image into a Circle"
        }
    }
}
