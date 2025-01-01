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
    /// - Returns: a cropped `UnifiedImage`
    /// - Throws: `MediaUtilitiesError.cropImageError` depending on the error
    static func cropImage(_ image: UnifiedImage, to size: CGRect, using maskShape: MaskShape) throws -> UnifiedImage {
        guard let image = image.withCorrectOrientation else {
            throw MediaUtilitiesError.cropImageError("couldn't get correct orientation")
        }
        guard let cgImage = image.cgImage else {
            throw MediaUtilitiesError.cropImageError("couldn't get cgImage")
        }
        guard let croppedCGImage = cgImage.cropping(to: size) else {
            throw MediaUtilitiesError.cropImageError("couldn't crop cgImage")
        }
        var croppedImage = UnifiedImage(cgImage: croppedCGImage)
        if maskShape == .circular {
            guard let croppedCircleImage = croppedImage.cropToCircle() else {
                throw MediaUtilitiesError.cropImageError("couldn't crop image to circle")
            }
            croppedImage = croppedCircleImage
        }
        return croppedImage
    }
    
    
    /// rotates the specified image by the specified angle,
    /// use this for 90 and 180 degree rotations,
    /// any other angle will result to a distorted image when a couple times
    /// - Parameters:
    ///   - image: image to be rotated
    ///   - angle: desired angle (90, -90, 180)
    /// - Returns: a rotated `UnifiedImage`
    /// - Throws: `MediaUtilitiesError.rotateImageError` depending on the error
    static func rotateImage(_ image: UnifiedImage, angle: Measurement<UnitAngle>) throws -> UnifiedImage {
        guard let image = image.withCorrectOrientation else {
            throw MediaUtilitiesError.rotateImageError("couldn't get correct orientation")
        }
        guard let cgImage = image.cgImage else {
            throw MediaUtilitiesError.rotateImageError("couldn't get cgImage")
        }
        let ciImage = CIImage(cgImage: cgImage)
        let rotationInRadians = angle.converted(to: .radians).value
        let rotatedRect = ciImage.extent.applying(CGAffineTransform(rotationAngle: CGFloat(rotationInRadians)))
        
        let translateX = -rotatedRect.origin.x
        let translateY = -rotatedRect.origin.y
        
        let rotationTransform = CGAffineTransform(rotationAngle: CGFloat(rotationInRadians))
        rotationTransform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
        
        let transformedImage = ciImage.transformed(by: rotationTransform)
        
        let context = CIContext()
        guard let outputCGImage = context.createCGImage(transformedImage, from: transformedImage.extent) else {
            throw MediaUtilitiesError.rotateImageError("couldn't create CGImage from transformed CIImage")
        }
        return UnifiedImage(cgImage: outputCGImage)
    }
}
