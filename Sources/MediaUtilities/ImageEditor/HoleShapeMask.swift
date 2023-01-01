//
//  SwiftUIView.swift
//  
//
//  Created by Ian on 01/01/2023.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
func HoleShapeMask(screenSize: CGSize, inset: CGFloat, desiredAspectRatio: CGFloat) -> Path {
    let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
    var insetRect: CGRect {
        let oneSideW = rect.maxX - (inset * 2)
        let oneSideH = oneSideW * desiredAspectRatio
        let halfSideX = oneSideW / 2
        let halfSideY = oneSideH / 2
        let insetRect = CGRect(
            x: (rect.maxX / 2) - halfSideX,
            y: (rect.maxY / 2) - halfSideY,
            width: oneSideW,
            height: oneSideH
        )
        if oneSideH > rect.maxY {
            let oneSideH1 = rect.maxY - (inset * 2)
            let oneSideW1 = oneSideH1 * 1 / desiredAspectRatio

            let halfSideX1 = oneSideW1 / 2
            let halfSideY1 = oneSideH1 / 2
            let insetRect1 = CGRect(
                x: (rect.maxX / 2) - halfSideX1,
                y: (rect.maxY / 2) - halfSideY1,
                width: oneSideW1,
                height: oneSideH1
            )
            return insetRect1
        }
        return insetRect
    }

    var shape = Rectangle().path(in: rect)
    shape.addPath(Rectangle().path(in: insetRect))

    return shape
}
