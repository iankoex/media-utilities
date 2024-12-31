//
//  WhiteGridOverlay.swift
//  
//
//  Created by Ian on 01/01/2023.
//

import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
struct WhiteGridOverlay: View {
    var screenSize: CGSize
    var inset: CGFloat
    var desiredAspectRatio: CGFloat
    var maskShape: MaskShape
    
    private var whiteOverlayRect: CGRect {
        let oneSideWidth = screenSize.width - (inset * 2)
        let oneSideHeight = oneSideWidth * desiredAspectRatio
        
        if oneSideHeight > screenSize.height {
            let adjustedHeight = screenSize.height - (inset * 2)
            let adjustedWidth = adjustedHeight * 1 / desiredAspectRatio
            return CGRect(x: 0, y: 0, width: adjustedWidth, height: adjustedHeight)
        } else {
            return CGRect(x: 0, y: 0, width: oneSideWidth, height: oneSideHeight)
        }
    }
    
    private var whiteOverlayRectOffset: CGSize {
        let rect = whiteOverlayRect
        return CGSize(width: (screenSize.width - rect.width) / 2, height: (screenSize.height - rect.height) / 2)
    }
    
    private var gridLines: [(start: CGPoint, end: CGPoint)] {
        let rect = whiteOverlayRect
        let p1 = CGPoint(x: rect.minX, y: rect.minY)
        let p2 = CGPoint(x: rect.maxX, y: rect.minY)
        let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let p4 = CGPoint(x: rect.minX, y: rect.maxY)
        let p5 = CGPoint(x: rect.minX, y: rect.maxY / 3)
        let p6 = CGPoint(x: rect.minX, y: rect.maxY * 2 / 3)
        let p7 = CGPoint(x: rect.maxX, y: rect.maxY / 3)
        let p8 = CGPoint(x: rect.maxX, y: rect.maxY * 2 / 3)
        let p9 = CGPoint(x: rect.maxX / 3, y: rect.minY)
        let p10 = CGPoint(x: rect.maxX * 2 / 3, y: rect.minY)
        let p11 = CGPoint(x: rect.maxX / 3, y: rect.maxY)
        let p12 = CGPoint(x: rect.maxX * 2 / 3, y: rect.maxY)
        
        return [
            // Outer rectangle lines for grid purposes (these will be ignored when mask is circular)
            (p1, p2), (p2, p3), (p3, p4), (p4, p1),
            
            // Vertical grid lines
            (p5, p7), (p6, p8),
            
            // Horizontal grid lines
            (p9, p11), (p10, p12)
        ]
    }
    
    private var gridOverlayPath: Path {
        let path = Path { path in
            let lines = gridLines
            for line in lines {
                path.move(to: line.start)
                path.addLine(to: line.end)
            }
        }
        return path
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            // Draw border
            whiteGridOverlayBorder
                .strokedPath(.init(lineWidth: 1.5))
                .fill(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(whiteOverlayRectOffset)
            
            // Mask with grid
            whiteGridOverlayBorder
                .fill(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(whiteOverlayRectOffset)
                .mask(
                    gridOverlayPath
                        .stroke(.white, lineWidth: 1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(whiteOverlayRectOffset)
                )
        }
    }
    
    private var whiteGridOverlayBorder: Path {
        let path = Path { path in
            let insetRect = whiteOverlayRect
            if maskShape == .circular {
                let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
                let radius = min(insetRect.width, insetRect.height) / 2
                path.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .degrees(360), clockwise: true)
            } else {
                path.addRect(insetRect)
            }
            path.closeSubpath()
        }
        return path
    }
}
