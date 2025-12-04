//
//  UnifiedImage.swift
//  MediaUtilities
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI

// MARK: - Unified Image Type

/// A cross-platform image type that provides unified access to image functionality
/// across iOS and macOS platforms.
///
/// `UnifiedImage` is a type alias that maps to the appropriate platform-specific
/// image type (`UIImage` on iOS, `NSImage` on macOS). This allows for consistent
/// image handling across platforms while maintaining access to platform-specific features.
///
/// ## Usage
///
/// ```swift
/// // Create a SwiftUI Image from UnifiedImage
/// let swiftUIImage = Image(unifiedImage: myUnifiedImage)
///
/// // Access platform-specific properties
/// #if os(iOS)
/// let uiImage = myUnifiedImage as UIImage
/// #else
/// let nsImage = myUnifiedImage as NSImage
/// #endif
/// ```
///
/// ## Platform Availability
///
/// - iOS 13.0+ (as `UIImage`)
/// - macOS 10.15+ (as `NSImage`)
///
#if os(iOS)
import UIKit

public typealias UnifiedImage = UIImage

/// SwiftUI Image extensions for cross-platform compatibility.
///
/// This extension provides convenient initializers for creating SwiftUI `Image`
/// instances from `UnifiedImage` types, handling platform differences automatically.
@available(iOS 13.0, macOS 10.15, *)
public extension Image {
    /// Creates a SwiftUI Image from a UnifiedImage.
    ///
    /// This initializer automatically handles the platform-specific conversion
    /// from `UnifiedImage` to SwiftUI's `Image` type.
    ///
    /// - Parameter unifiedImage: The unified image to convert to a SwiftUI Image
    init(unifiedImage: UnifiedImage) {
        self.init(uiImage: unifiedImage)
    }
}

extension UIImage {
    /// Crops the image to a circular shape.
    ///
    /// This method creates a circular version of the image by cropping it to a square
    /// (using the smaller dimension) and applying a circular mask. The resulting image
    /// will be circular with transparent corners.
    ///
    /// - Returns: A new `UIImage` cropped to circular shape, or `nil` if cropping fails
    ///
    /// - Note: The output image will be square with the diameter equal to the smaller
    ///   dimension of the input image.
    func cropToCircle() -> UIImage? {
        let imageSize = self.size
        let diameter = min(imageSize.width, imageSize.height)
        let circleRect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        
        UIGraphicsBeginImageContextWithOptions(circleRect.size, false, 0.0)
        let context = UIGraphicsGetCurrentContext()
        
        let path = UIBezierPath(ovalIn: circleRect)
        context?.addPath(path.cgPath)
        context?.clip()
        
        self.draw(in: CGRect(
            x: -((imageSize.width - diameter) / 2),
            y: -((imageSize.height - diameter) / 2),
            width: imageSize.width,
            height: imageSize.height
        ))
        
        let circularImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return circularImage
    }
}

extension UIImage {
    /// Returns the image with corrected orientation.
    ///
    /// This property normalizes the image orientation to `.up`, ensuring that
    /// the image data matches its visual orientation. This is important for
    /// consistent image processing and display.
    ///
    /// - Returns: A new `UIImage` with corrected orientation, or `nil` if correction fails
    ///
    /// - Note: If the image is already oriented correctly (`.up`), returns the original image.
    var withCorrectOrientation: UIImage? {
        if imageOrientation == .up { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
#endif

#if os(macOS)
import AppKit

public typealias UnifiedImage = NSImage

/// SwiftUI Image extensions for cross-platform compatibility.
///
/// This extension provides convenient initializers for creating SwiftUI `Image`
/// instances from `UnifiedImage` types, handling platform differences automatically.
@available(iOS 13.0, macOS 10.15, *)
public extension Image {
    /// Creates a SwiftUI Image from a UnifiedImage.
    ///
    /// This initializer automatically handles the platform-specific conversion
    /// from `UnifiedImage` to SwiftUI's `Image` type.
    ///
    /// - Parameter unifiedImage: The unified image to convert to a SwiftUI Image
    init(unifiedImage: UnifiedImage) {
        self.init(nsImage: unifiedImage)
    }
}

extension NSImage {
    /// Creates an NSImage from a CGImage.
    ///
    /// This convenience initializer creates an NSImage from a CGImage,
    /// automatically determining the appropriate size.
    ///
    /// - Parameter cgImage: The CGImage to convert to NSImage
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}

extension NSImage {
    /// Returns the CGImage representation of the NSImage.
    ///
    /// This computed property provides access to the underlying CGImage
    /// for Core Graphics operations and cross-platform compatibility.
    ///
    /// - Returns: The CGImage representation, or `nil` if conversion fails
    var cgImage: CGImage? {
        var rect = NSRect(origin: CGPoint(x: 0, y: 0), size: self.size)
        return self.cgImage(forProposedRect: &rect, context: NSGraphicsContext.current, hints: nil)
    }
}

extension NSImage {
    /// Crops the image to a circular shape.
    ///
    /// This method creates a circular version of the image by cropping it to a square
    /// (using the smaller dimension) and applying a circular mask. The resulting image
    /// will be circular with transparent corners.
    ///
    /// - Returns: A new `NSImage` cropped to circular shape, or `nil` if cropping fails
    ///
    /// - Note: The output image will be square with the diameter equal to the smaller
    ///   dimension of the input image.
    func cropToCircle() -> NSImage? {
        let imageSize = self.size
        let diameter = min(imageSize.width, imageSize.height)
        let circleRect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        
        let croppedImage = NSImage(size: circleRect.size)
        croppedImage.lockFocus()
        
        let path = NSBezierPath(ovalIn: circleRect)
        path.addClip()
        
        self.draw(in: NSRect(
            x: -((imageSize.width - diameter) / 2),
            y: -((imageSize.height - diameter) / 2),
            width: imageSize.width,
            height: imageSize.height
        ))
        
        croppedImage.unlockFocus()
        return croppedImage
    }
}

extension NSImage {
    /// Returns the image with corrected orientation.
    ///
    /// This property provides compatibility with iOS image orientation handling.
    /// On macOS, image orientation issues are less common, so this typically
    /// returns the original image unchanged.
    ///
    /// - Returns: The original `NSImage` (orientation correction is typically not needed on macOS)
    ///
    /// - Note: macOS handles image orientation differently than iOS, so this property
    ///   usually returns the original image unchanged.
    var withCorrectOrientation: NSImage? {
        return self
    }
}
#endif
