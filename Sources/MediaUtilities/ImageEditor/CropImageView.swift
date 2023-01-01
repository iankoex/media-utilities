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

    @State private var imageAspectRatio: CGFloat = 0.0
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
                    HoleShapeMask(screenSize: screenSize, inset: inset, desiredAspectRatio: desiredAspectRatio)
                        .fill(style: FillStyle(eoFill: true))
                 )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            WhiteGridOverlay(screenSize: screenSize, inset: inset, desiredAspectRatio: desiredAspectRatio)
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
        imageAspectRatio = w / h
        resetImageOriginAndScale(screenSize: screenSize)
    }
    
    private func resetImageOriginAndScale(screenSize: CGSize) {
        withAnimation(.easeInOut) {
            if imageAspectRatio > screenAspectRatio {
                displayWidth = screenSize.width
                displayWeight = displayWidth / imageAspectRatio
            } else {
                displayWeight = screenSize.height
                displayWidth = displayWeight * imageAspectRatio
            }
            currentAmount = 0
            finalAmount = 1
            currentPosition = .zero
            newPosition = .zero
        }
    }
    
    private func repositionImage(screenSize: CGSize) {
        let screenWidth = screenSize.width
        
        if imageAspectRatio > screenAspectRatio {
            displayWidth = screenSize.width * finalAmount
            displayWeight = displayWidth / imageAspectRatio
        } else {
            displayWeight = screenSize.height * finalAmount
            displayWidth = displayWeight * imageAspectRatio
        }
        horizontalOffset = (displayWidth - screenWidth ) / 2
        verticalOffset = (displayWeight - (screenWidth * desiredAspectRatio)) / 2
        
        if finalAmount > 10.0 {
            withAnimation {
                finalAmount = 10.0
            }
        }
        
        if displayWidth >= screenSize.width {
            if newPosition.width > horizontalOffset {
                print(1)
                withAnimation(.easeInOut) {
                    newPosition = CGSize(width: horizontalOffset + inset, height: newPosition.height)
                    currentPosition = CGSize(width: horizontalOffset + inset, height: currentPosition.height)
                }
            }
            
            if newPosition.width < (horizontalOffset * -1) {
                print(2)
                withAnimation(.easeInOut) {
                    newPosition = CGSize(width: ( horizontalOffset * -1) - inset, height: newPosition.height)
                    currentPosition = CGSize(width: ( horizontalOffset * -1 - inset), height: currentPosition.height)
                }
            }
        } else {
            withAnimation(.easeInOut) {
                print(3)
                newPosition = CGSize(width: 0, height: newPosition.height)
                currentPosition = CGSize(width: 0, height: newPosition.height)
            }
        }
        
//        if displayWeight >= screenSize.width {
//            if newPosition.height > verticalOffset {
//                print(4)
//                withAnimation(.easeInOut) {
//                    newPosition = CGSize(width: newPosition.width, height: verticalOffset + inset)
//                    currentPosition = CGSize(width: newPosition.width, height: verticalOffset + inset)
//                }
//            }
//            if newPosition.height < (verticalOffset * -0.1) {
//                print(5)
//                withAnimation(.easeInOut) {
//                    newPosition = CGSize(width: newPosition.width, height: (verticalOffset * -0.1) - inset)
//                    currentPosition = CGSize(width: newPosition.width, height: (verticalOffset * -0.1) - inset)
//                }
//            }
//        } else {
//            withAnimation (.easeInOut) {
//                print(6)
//                newPosition = CGSize(width: newPosition.width, height: 0)
//                currentPosition = CGSize(width: newPosition.width, height: 0)
//            }
//        }
        
        if displayWidth < screenSize.width && imageAspectRatio > screenAspectRatio {
            print(7)
            resetImageOriginAndScale(screenSize: screenSize)
        }
        if displayWeight < screenSize.height && imageAspectRatio < screenAspectRatio {
            print(8)
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
