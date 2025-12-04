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

/// A collection of static utility functions for image manipulation and processing.
///
/// `MediaUtilities` provides core image processing functionality including cropping,
/// rotation, and straightening operations. All functions are static and work with
/// the unified `UnifiedImage` type for cross-platform compatibility.
///
/// ## Usage
///
/// ```swift
/// // Crop an image to a specific size
/// let croppedImage = try MediaUtilities.cropImage(
///     originalImage,
///     to: CGRect(x: 0, y: 0, width: 200, height: 200),
///     using: .rectangular
/// )
///
/// // Rotate an image by 90 degrees
/// let rotatedImage = try MediaUtilities.rotateImage(
///     originalImage,
///     angle: Measurement(value: 90, unit: .degrees)
/// )
/// ```
///
/// ## Platform Availability
///
/// - iOS 13.0+
/// - macOS 10.15+
///
public struct MediaUtilities {
    
    /// Crops an image to a specified rectangular region with optional circular masking.
    ///
    /// This function crops the input image to the specified rectangular region and optionally
    /// applies a circular mask to create a circular image. The function preserves image
    /// orientation and handles platform-specific image processing.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Crop to a rectangular region
    /// let cropped = try MediaUtilities.cropImage(
    ///     image,
    ///     to: CGRect(x: 100, y: 100, width: 200, height: 200),
    ///     using: .rectangular
    /// )
    ///
    /// // Crop to a circular region
    /// let circular = try MediaUtilities.cropImage(
    ///     image,
    ///     to: CGRect(x: 100, y: 100, width: 200, height: 200),
    ///     using: .circular
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - image: The image to crop
    ///   - size: The rectangular region to crop to, specified in image coordinates
    ///   - maskShape: The shape to apply after cropping. `.circular` creates a circular image,
    ///     `.rectangular` leaves the image as a rectangle
    /// - Returns: A new `UnifiedImage` containing the cropped result
    /// - Throws: `MediaUtilitiesError.cropImageError` if cropping fails due to invalid input or processing errors
    public static func cropImage(_ image: UnifiedImage, to size: CGRect, using maskShape: MaskShape) throws -> UnifiedImage {
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
    
    
    /// Rotates an image by a specified angle.
    ///
    /// This function rotates the input image by the specified angle using Core Image
    /// transformations. It's optimized for 90-degree and 180-degree rotations, but
    /// can handle arbitrary angles. For non-orthogonal rotations, repeated applications
    /// may result in image distortion due to cumulative transformation errors.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Rotate by 90 degrees clockwise
    /// let rotated = try MediaUtilities.rotateImage(
    ///     image,
    ///     angle: Measurement(value: 90, unit: .degrees)
    /// )
    ///
    /// // Rotate by 180 degrees
    /// let upsideDown = try MediaUtilities.rotateImage(
    ///     image,
    ///     angle: Measurement(value: 180, unit: .degrees)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - image: The image to rotate
    ///   - angle: The rotation angle as a `Measurement<UnitAngle>`. Positive values rotate clockwise
    /// - Returns: A new `UnifiedImage` containing the rotated result
    /// - Throws: `MediaUtilitiesError.rotateImageError` if rotation fails due to invalid input or processing errors
    ///
    /// - Note: For best results, use 90-degree increments. Arbitrary angles may accumulate distortion with repeated rotations.
    public static func rotateImage(_ image: UnifiedImage, angle: Measurement<UnitAngle>) throws -> UnifiedImage {
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
    
    /// Straightens an image by correcting perspective distortion.
    ///
    /// This function applies a straightening filter to correct perspective distortion
    /// in images. Unlike rotation, straightening adjusts the image content to
    /// compensate for camera tilt while maintaining the original dimensions.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Straighten a slightly tilted image
    /// let straightened = try MediaUtilities.straightenImage(
    ///     tiltedImage,
    ///     angle: Measurement(value: 5, unit: .degrees)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - image: The image to straighten
    ///   - angle: The correction angle as a `Measurement<UnitAngle>`. Small angles (typically < 10°) work best
    /// - Returns: A new `UnifiedImage` with perspective correction applied
    /// - Throws: `MediaUtilitiesError.straightenImageError` if straightening fails due to invalid input or processing errors
    ///
    /// - Note: This function uses Core Image's CIStraightenFilter. Results may vary based on image content and angle.
    /// - Warning: This API is currently in development and may change in future versions.
    public static func straightenImage(_ image: UnifiedImage, angle: Measurement<UnitAngle>) throws -> UnifiedImage {
        guard let image = image.withCorrectOrientation else {
            throw MediaUtilitiesError.straightenImageError("couldn't get correct orientation")
        }
        guard let cgImage = image.cgImage else {
            throw MediaUtilitiesError.straightenImageError("couldn't get cgImage")
        }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIStraightenFilter") else {
            throw MediaUtilitiesError.badImage
        }
        let rotationInRadians = angle.converted(to: .radians).value
        filter.setDefaults()
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(rotationInRadians, forKey: kCIInputAngleKey)
        guard let outputImage = filter.outputImage else {
            throw MediaUtilitiesError.badImage
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw MediaUtilitiesError.straightenImageError("couldn't create CGImage from CIImage")
        }
        return UnifiedImage(cgImage: cgImage)
    }
}
