//
//  UnifiedImage.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI

#if os(iOS)
import UIKit

public typealias UnifiedImage = UIImage

@available(iOS 13.0, macOS 10.15, *)
public extension Image {
    init(unifiedImage: UnifiedImage) {
        self.init(uiImage: unifiedImage)
    }
}

extension UIImage {
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

@available(iOS 13.0, macOS 10.15, *)
public extension Image {
    init(unifiedImage: UnifiedImage) {
        self.init(nsImage: unifiedImage)
    }
}

extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: .zero)
    }
}

extension NSImage {
    var cgImage: CGImage? {
        var rect = NSRect(origin: CGPoint(x: 0, y: 0), size: self.size)
        return self.cgImage(forProposedRect: &rect, context: NSGraphicsContext.current, hints: nil)
    }
}

extension NSImage {
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
    
    // overloads
    // haven't seen this issue in macOS
    var withCorrectOrientation: NSImage? {
        return self
    }
}
#endif
