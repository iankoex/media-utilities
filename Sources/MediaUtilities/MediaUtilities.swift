//
//  MediaUtilities.swift
//  MediaUtilities
//
//  Created by Ian on 27/03/2022.
//

import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public struct MediaUtilities {
    
    /// Crops Image to a specified size using a  specified mask shape
    /// - Parameters:
    ///   - image: image to crop
    ///   - size: desired image size
    ///   - maskShape: desired image shape, circular will crop the image to a circle, rectangular does nothing
    /// - Returns: UnifiedImage
    /// - Throws: `MediaUtilitiesError` depending on the error
    static func cropImage(_ image: UnifiedImage, to size: CGRect, using maskShape: MaskShape) throws -> UnifiedImage {
        guard let image = image.withCorrectOrientation else {
            throw MediaUtilitiesError.failedToGetImageWithCorrectOrientation
        }
        guard let cgImage = image.cgImage else {
            throw MediaUtilitiesError.failedToGetCGImageFromUnifiedImage
        }
        guard let croppedCGImage = cgImage.cropping(to: size) else {
            throw MediaUtilitiesError.failedToCropCGImage
        }
        var croppedImage = UnifiedImage(cgImage: croppedCGImage)
        if maskShape == .circular {
            guard let croppedCircleImage = croppedImage.cropToCircle() else {
                throw MediaUtilitiesError.failedToCropImageIntoACircle
            }
            croppedImage = croppedCircleImage
        }
        return croppedImage
    }
}
