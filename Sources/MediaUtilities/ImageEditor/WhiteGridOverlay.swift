//
//  SwiftUIView.swift
//  
//
//  Created by Ian on 01/01/2023.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
struct WhiteGridOverlay: View {
    var screenSize: CGSize
    var inset: CGFloat
    var desiredAspectRatio: CGFloat
    
    var body: some View {
        whiteGridOverlay
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(whiteOverayRectOffset)
    }

    var whiteGridOverlay: some Shape {
        let insetRect = whiteOverayRect
        let p1 = CGPoint(x: insetRect.minX, y: insetRect.minY)
        let p2 = CGPoint(x: insetRect.maxX, y: insetRect.minY)
        let p3 = CGPoint(x: insetRect.maxX, y: insetRect.maxY)
        let p4 = CGPoint(x: insetRect.minX, y: insetRect.maxY)
        let p5 = CGPoint(x: insetRect.minX, y: insetRect.maxY * 1/3)
        let p6 = CGPoint(x: insetRect.minX, y: insetRect.maxY * 2/3)
        let p7 = CGPoint(x: insetRect.maxX, y: insetRect.maxY * 1/3)
        let p8 = CGPoint(x: insetRect.maxX, y: insetRect.maxY * 2/3)
        let p9 = CGPoint(x: insetRect.maxX * 1/3, y: insetRect.minY)
        let p10 = CGPoint(x: insetRect.maxX * 2/3, y: insetRect.minY)
        let p11 = CGPoint(x: insetRect.maxX * 1/3, y: insetRect.maxY)
        let p12 = CGPoint(x: insetRect.maxX * 2/3, y: insetRect.maxY)

        var path = Path()

        path.move(to: p1)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.addLine(to: p1)
        path.move(to: p5)
        path.addLine(to: p5)
        path.addLine(to: p7)
        path.move(to: p6)
        path.addLine(to: p6)
        path.addLine(to: p8)
        path.move(to: p9)
        path.addLine(to: p9)
        path.addLine(to: p11)
        path.move(to: p10)
        path.addLine(to: p10)
        path.addLine(to: p12)

        path = path.strokedPath(.init(lineWidth: 2))
        path.closeSubpath()
        return path
    }

    var whiteOverayRect: CGRect {
        let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        let oneSideW = rect.maxX - (inset * 2)
        let oneSideH = oneSideW * desiredAspectRatio
        let insetRect = CGRect(
            x: 0,
            y: 0,
            width: oneSideW,
            height: oneSideH
        )
        if oneSideH > rect.maxY {
            let rect1 = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
            let oneSideH1 = rect1.maxY - (inset * 2)
            let oneSideW1 = oneSideH1 * 1 / desiredAspectRatio

            let insetRect1 = CGRect(
                x: 0,
                y: 0,
                width: oneSideW1,
                height: oneSideH1
            )
            return insetRect1
        }
        return insetRect
    }

    var whiteOverayRectOffset: CGSize {
        let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        let oneSideW = rect.maxX - (inset * 2)
        let oneSideH = oneSideW * desiredAspectRatio
        let halfSideX = oneSideW / 2
        let halfSideY = oneSideH / 2
        let insetRectOffset = CGSize(
            width: (rect.maxX / 2) - halfSideX,
            height: (rect.maxY / 2) - halfSideY
        )
        if oneSideH > rect.maxY {
            let rect1 = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
            let oneSideH1 = rect1.maxY - (inset * 2)
            let oneSideW1 = oneSideH1 * 1 / desiredAspectRatio

            let halfSideX1 = oneSideW1 / 2
            let halfSideY1 = oneSideH1 / 2
            let insetRectOffset1 = CGSize(
                width: (rect1.maxX / 2) - halfSideX1,
                height: (rect1.maxY / 2) - halfSideY1
            )
            return insetRectOffset1
        }
        return insetRectOffset
    }
}
