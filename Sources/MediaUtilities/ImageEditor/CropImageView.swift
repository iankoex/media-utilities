//
//  CropImageView.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@available(iOS 14.0, macOS 11, *)
public struct CropImageView: View {
    @Binding var isPresented: Bool
    var inputImage: UnifiedImage
    var desiredAspectRatio: CGFloat
    var cancelPressed: () -> Void
    var onCompletion: (UnifiedImage) -> Void

    public init(
        _ isPresented: Binding<Bool>,
        inputImage: UnifiedImage,
        desiredAspectRatio: CGFloat,
        cancelPressed: @escaping () -> Void,
        onCompletion: @escaping (UnifiedImage) -> Void
    ) {
        self._isPresented = isPresented
        self.inputImage = inputImage
        self.desiredAspectRatio = 1 / desiredAspectRatio
        self.cancelPressed = cancelPressed
        self.onCompletion = onCompletion
    }

    @State private var selectedAspectRatio: CGFloat = 0.0
    @State private var displayWidth: CGFloat = 0.0
    @State private var displayWeight: CGFloat = 0.0
    @State private var screenSize: CGSize = .zero
    @State private var screenAspectRatio: CGFloat = 0.0
    @State private var isDraggingImage: Bool = false
    let inset: CGFloat = 20
   
    //Zoom Scale and Drag...
    @State private var currentAmount: CGFloat = 0
    @State private var finalAmount: CGFloat = 1
    @State private var currentPosition: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0.0
    @State private var verticalOffset: CGFloat = 0.0
    
    public var body: some View {
        contents
            .readViewSize(onChange: setScreenParticulars(_:))
    }
    
    var contents: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(unifiedImage: inputImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(finalAmount + currentAmount)
                    .offset(x: self.currentPosition.width, y: self.currentPosition.height)
            }

            Rectangle()
                .fill(Color.black.opacity(0.8))
//                .fill(Color.black.opacity(0.3))
                .mask(
                    HoleShapeMask(screenSize: screenSize)
                        .fill(style: FillStyle(eoFill: true))
                 )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            whiteGridOverlay
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            cropImageViewOverlay
        }
        .gesture(magGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var cropImageViewOverlay: some View {
        VStack {
            HStack {
                EditorControlButton("xmark.circle", action: {
                    isPresented = false
                })
                Spacer()
                Text("Move and Scale")
                Spacer()
                EditorControlButton("checkmark.circle", action: cropImage)
            }
            .padding(.top)
            .opacity(isDraggingImage ? 0 : 1)
            Spacer()
            bottomButtons
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal)
    }
    
    var bottomButtons: some View {
        HStack {
            Spacer()
            #if os(macOS)
            HStack {
                Slider(value: $finalAmount, in: 1...5, label: {
                    Text("Scale: \(Int(finalAmount * 100/5))%")
                }, minimumValueLabel: {
                    Text("min")
                }, maximumValueLabel: {
                    Text("max")
                }, onEditingChanged: { isEd in
                    if !isEd {
                        repositionImage(screenSize: screenSize)
                    }
                })
                .frame(width: 250)
            }
            #endif
            Spacer()
        }
        .padding(10)
    }
    
    var magGesture: some Gesture {
        MagnificationGesture()
            .onChanged { amount in
                setIsDraggingImage(to: true)
                self.currentAmount = amount - 1
            }
            .onEnded { amount in
                setIsDraggingImage(to: false)
                self.finalAmount += self.currentAmount
                self.currentAmount = 0
                repositionImage(screenSize: screenSize)
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                setIsDraggingImage(to: true)
                self.currentPosition = CGSize(
                    width: value.translation.width + self.newPosition.width,
                    height: value.translation.height + self.newPosition.height
                )
            }
            .onEnded { value in
                setIsDraggingImage(to: false)
                self.currentPosition = CGSize(
                    width: value.translation.width + self.newPosition.width,
                    height: value.translation.height + self.newPosition.height
                )
                self.newPosition = self.currentPosition
                repositionImage(screenSize: screenSize)
            }
    }
    
    var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                resetImageOriginAndScale(screenSize: screenSize)
            }
    }
    
    private func setScreenParticulars(_ size: CGSize) {
        screenSize = size
        screenAspectRatio = size.width / size.height
        let w = inputImage.size.width
        let h = inputImage.size.height
        selectedAspectRatio = w / h
        resetImageOriginAndScale(screenSize: screenSize)
    }
    
    func HoleShapeMask(screenSize: CGSize) -> Path {
        let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        var shape = Rectangle().path(in: rect)
        shape.addPath(Rectangle().path(in: insetRect))

        return shape
    }

    var whiteGridOverlay: some Shape {
        let insetRect = insetRect
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
        print("Min", insetRect.minX, insetRect.minX)

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

    var insetRect: CGRect {
        let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
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
            print("HIGH")
            let rect1 = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
            let oneSideH1 = rect1.maxY - (inset * 2)
            let oneSideW1 = oneSideH1 * 1 / desiredAspectRatio

            let halfSideX1 = oneSideW1 / 2
            let halfSideY1 = oneSideH1 / 2
            let insetRect1 = CGRect(
                x: (rect1.maxX / 2) - halfSideX1,
                y: (rect1.maxY / 2) - halfSideY1,
                width: oneSideW1,
                height: oneSideH1
            )
            return insetRect1
        }
        return insetRect
    }
    
    private func resetImageOriginAndScale(screenSize: CGSize) {
        withAnimation(.easeInOut) {
            if selectedAspectRatio > screenAspectRatio {
                displayWidth = screenSize.width
                displayWeight = displayWidth / selectedAspectRatio
            } else {
                displayWeight = screenSize.height
                displayWidth = displayWeight * selectedAspectRatio
            }
            currentAmount = 0
            finalAmount = 1
            currentPosition = .zero
            newPosition = .zero
        }
    }
    
    private func repositionImage(screenSize: CGSize) {
        let screenWidth = screenSize.width
        
        if selectedAspectRatio > screenAspectRatio {
            displayWidth = screenSize.width * finalAmount
            displayWeight = displayWidth / selectedAspectRatio
        } else {
            displayWeight = screenSize.height * finalAmount
            displayWidth = displayWeight * selectedAspectRatio
        }
        horizontalOffset = (displayWidth - screenWidth ) / 2
        verticalOffset = ( displayWeight - (screenWidth * desiredAspectRatio) ) / 2
        
        if finalAmount > 10.0 {
            withAnimation {
                finalAmount = 10.0
            }
        }
        
        if displayWidth >= screenSize.width {
            if newPosition.width > horizontalOffset {
                withAnimation(.easeInOut) {
                    newPosition = CGSize(width: horizontalOffset + inset, height: newPosition.height)
                    currentPosition = CGSize(width: horizontalOffset + inset, height: currentPosition.height)
                }
            }
            
            if newPosition.width < ( horizontalOffset * -1) {
                withAnimation(.easeInOut){
                    newPosition = CGSize(width: ( horizontalOffset * -1) - inset, height: newPosition.height)
                    currentPosition = CGSize(width: ( horizontalOffset * -1 - inset), height: currentPosition.height)
                }
            }
        } else {
            withAnimation(.easeInOut) {
                newPosition = CGSize(width: 0, height: newPosition.height)
                currentPosition = CGSize(width: 0, height: newPosition.height)
            }
        }
        
        if displayWeight >= screenSize.width {
            if newPosition.height > verticalOffset {
                withAnimation(.easeInOut){
                    newPosition = CGSize(width: newPosition.width, height: verticalOffset + inset)
                    currentPosition = CGSize(width: newPosition.width, height: verticalOffset + inset)
                }
            }
            if newPosition.height < ( verticalOffset * -1) {
                withAnimation(.easeInOut){
                    newPosition = CGSize(width: newPosition.width, height: ( verticalOffset * -1) - inset)
                    currentPosition = CGSize(width: newPosition.width, height: ( verticalOffset * -1) - inset)
                }
            }
        } else {
            withAnimation (.easeInOut){
                newPosition = CGSize(width: newPosition.width, height: 0)
                currentPosition = CGSize(width: newPosition.width, height: 0)
            }
        }
        
        if displayWidth < screenSize.width && selectedAspectRatio > screenAspectRatio {
            resetImageOriginAndScale(screenSize: screenSize)
        }
        if displayWeight < screenSize.height && selectedAspectRatio < screenAspectRatio {
            resetImageOriginAndScale(screenSize: screenSize)
        }
    }

    private func setIsDraggingImage(to bool: Bool) {
        withAnimation(.spring()) {
            isDraggingImage = bool
        }
    }

    private func cropImage() {
        let scale = (inputImage.size.width) / displayWidth
        let xPos = ( ( ( displayWidth - screenSize.width ) / 2 ) + inset + ( currentPosition.width * -1 ) ) * scale
        let yPos = ( ( ( displayWeight - (screenSize.width * desiredAspectRatio) ) / 2  ) + inset + ( currentPosition.height * -1 ) ) * scale
        let radius = ( screenSize.width - inset * 2 ) * scale
        let radius1 = radius * desiredAspectRatio
        guard let img = imageFromCrop(image: inputImage, croppedTo: CGRect(x: xPos, y: yPos, width: radius, height: radius1)) else {
            // Err callback
            isPresented = false
            return
        }
        onCompletion(img)
        isPresented = false
    }
    
    #if os(iOS)
    private func imageFromCrop(image: UIImage, croppedTo rect: CGRect) -> UIImage? {
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        let drawRect = CGRect(x: -rect.origin.x, y: -rect.origin.y, width: image.size.width, height: image.size.height)
        context?.clip(to: CGRect(x: 0, y: 0, width: rect.size.width, height: rect.size.height))
        image.draw(in: drawRect)
        let subImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return subImage
     }
    #else

    private func imageFromCrop(image: NSImage, croppedTo rect: CGRect) -> NSImage? {
        let croppedImrect: CGRect = rect
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        var croppedImage = NSImage(named: "iconWhite")
        if let cropped = cgImage!.cropping(to: croppedImrect) {
            croppedImage = NSImage(cgImage: cropped, size: rect.size)
        }
        return croppedImage
    }
    #endif
}

@available(iOS 14.0, macOS 11, *)
struct Cropr_Previews: PreviewProvider {
    static var previews: some View {
        CropImageView(
            .constant(true),
            inputImage: UnifiedImage(named: "mac")!,
            desiredAspectRatio: 16/9,
            cancelPressed: {},
            onCompletion: { img in

            }
        )
    }
}
