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

@available(iOS 13.0, macOS 11, *)
public struct CropImageView: View {
    let inputImage: UnifiedImage
    let desiredAspectRatio: CGFloat
    let maskShape: MaskShape
    let cancelPressed: () -> Void
    let onCompletion: (Result<UnifiedImage, Error>) -> Void

    public init(
        inputImage: UnifiedImage,
        desiredAspectRatio: CGFloat,
        maskShape: MaskShape,
        cancelPressed: @escaping () -> Void,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) {
        self.inputImage = inputImage
        self.desiredAspectRatio = maskShape == .circular ? 1 : 1 / desiredAspectRatio
        self.maskShape = maskShape
        self.cancelPressed = cancelPressed
        self.onCompletion = onCompletion
    }

    @State private var screenSize: CGSize = .zero
    @State private var imageViewSize: CGSize = .zero
    let inset: CGFloat = 20
   
    //Zoom Scale and Drag...
    @State private var currentScaleAmount: CGFloat = 0
    @State private var finalScaleAmount: CGFloat = 1
    @State private var minScaleAmount: CGFloat = 1
    @State private var minScaleAmountSet: Bool = false
    @State private var currentPosition: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var isDraggingImage: Bool = false
    
    public var body: some View {
        contents
            .readViewSize(onChange: setScreenParticulars(_:))
    }
    
    var contents: some View {
        ZStack(alignment: .center) {
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            Image(unifiedImage: inputImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .readViewSize(onChange: setImageViewSize(_:))
                .scaleEffect(finalScaleAmount + currentScaleAmount)
                .offset(x: self.currentPosition.width, y: self.currentPosition.height)
            
            Rectangle()
                .fill(Color.black.opacity(isDraggingImage ? 0.3 : 0.8))
                .mask(
                    HoleShapeMask(
                        screenSize: screenSize,
                        inset: inset,
                        desiredAspectRatio: desiredAspectRatio,
                        maskShape: maskShape
                    )
                    .fill(style: FillStyle(eoFill: true))
                 )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
           
            WhiteGridOverlay(
                screenSize: screenSize,
                inset: inset,
                desiredAspectRatio: desiredAspectRatio,
                maskShape: maskShape
            )
            
            cropImageViewOverlay
        }
        .gesture(magGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    var cropImageViewOverlay: some View {
        VStack {
            HStack {
                EditorControlButton("xmark.circle", action: cancelPressed)
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
        .buttonStyle(.borderless)
        .foregroundColor(.white)
        .padding(.horizontal)
    }
    
    var bottomButtons: some View {
        HStack {
            Spacer()
            #if os(macOS)
            HStack {
                Slider(value: $finalScaleAmount, in: 1...5, label: {
                    Text("Scale: \(Int(finalScaleAmount * 100/5))%")
                }, minimumValueLabel: {
                    Text("min")
                }, maximumValueLabel: {
                    Text("max")
                }, onEditingChanged: { isEd in
                    if !isEd {
                        repositionImage()
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
                self.currentScaleAmount = amount - 1
            }
            .onEnded { amount in
                setIsDraggingImage(to: false)
                self.finalScaleAmount += self.currentScaleAmount
                self.currentScaleAmount = 0
                repositionImage()
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
                repositionImage()
            }
    }
    
    var tapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded(resetImageOriginAndScale)
    }
    
    private func setImageViewSize(_ size: CGSize) {
        guard imageViewSize != size else { return }
        imageViewSize = size
        scaleImagetoFit()
    }
    
    private func setScreenParticulars(_ size: CGSize) {
        screenSize = size
        resetImageOriginAndScale()
        scaleImagetoFit()
    }
    
    private func resetImageOriginAndScale() {
        withAnimation(.snappy()) {
            currentScaleAmount = 0
            finalScaleAmount = minScaleAmount
            currentPosition = .zero
            newPosition = .zero
        }
    }
    
    private var holeWidth: CGFloat {
        screenSize.width - (inset * 2)
    }
    
    private var holeHeight: CGFloat {
        holeWidth * desiredAspectRatio
    }
    
    private var heightOffsetLimit: CGFloat {
        (imageViewSize.height / 2 * finalScaleAmount) - (holeHeight / 2)
    }
    
    private var widthOffsetLimit: CGFloat {
        (imageViewSize.width / 2 * finalScaleAmount) - (holeWidth / 2)
    }
    
    /*
     this will be called periodically during dragging
     we dont watn to reset the finalScaleAmount and therefore
     we need measures to prevent that
     */
    private func scaleImagetoFit() {
        guard imageViewSize != .zero else {
            return
        }
        let widthScaleFactor = holeWidth / imageViewSize.width
        let heightScaleFactor = holeHeight / imageViewSize.height
        
        if imageViewSize.height < holeHeight {
            setMinScaleAmount(heightScaleFactor)
            setFinalScaleAmount(heightScaleFactor)
        } else if imageViewSize.width < holeWidth {
            setMinScaleAmount(widthScaleFactor)
            setFinalScaleAmount(widthScaleFactor)
        } else {
            let sc = max(heightScaleFactor, widthScaleFactor)
            setMinScaleAmount(sc)
        }
    }
    
    private func setMinScaleAmount(_ scale: CGFloat) {
        guard minScaleAmountSet == false else { return }
        minScaleAmount = scale
        finalScaleAmount = scale
        minScaleAmountSet = true
    }
    
    private func setFinalScaleAmount(_ scale: CGFloat) {
        guard scale > minScaleAmount else { return }
        finalScaleAmount = scale
    }
    
    private func repositionImage() {
        if finalScaleAmount > 10.0 {
            withAnimation(.snappy()) {
                finalScaleAmount = 10.0
            }
        }
        
        if finalScaleAmount < minScaleAmount {
            withAnimation(.snappy()) {
                finalScaleAmount = minScaleAmount
            }
        }
        
        // Leading
        if currentPosition.width > widthOffsetLimit {
            withAnimation(.snappy()) {
                currentPosition.width = widthOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Trailing
        if currentPosition.width < -widthOffsetLimit {
            withAnimation(.snappy()) {
                currentPosition.width = -widthOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Top
        if currentPosition.height > heightOffsetLimit {
            withAnimation(.snappy()) {
                currentPosition.height = heightOffsetLimit
                newPosition = currentPosition
            }
        }
        
        // Bottom
        if currentPosition.height < -heightOffsetLimit {
            withAnimation(.snappy()) {
                currentPosition.height = -heightOffsetLimit
                newPosition = currentPosition
            }
        }
    }

    private func setIsDraggingImage(to bool: Bool) {
        withAnimation(.snappy()) {
            isDraggingImage = bool
        }
    }

    private func cropImage() {
        let xScale = inputImage.size.width / (imageViewSize.width * finalScaleAmount)
        let yScale = inputImage.size.height / (imageViewSize.height * finalScaleAmount)
        
        let xPos = (widthOffsetLimit - currentPosition.width) * xScale
        let yPos = (heightOffsetLimit - currentPosition.height) * yScale
        let width = holeWidth * xScale
        let heigth = holeHeight * yScale
        
        let rect = CGRect(
            x: xPos,
            y: yPos,
            width: width,
            height: heigth
        )
        
        Task {
            do {
                let image = try MediaUtilities.cropImage(inputImage, to: rect, using: maskShape)
                onCompletion(.success(image))
            } catch {
                onCompletion(.failure(error))
            }
        }
    }
}

@available(iOS 14.0, macOS 11, *)
public struct Cropr_Previews: View {
    
    public init(){}
    
    public var body: some View {
        CropImageView(
            inputImage: UnifiedImage(named: "sunflower")!,
            desiredAspectRatio: 16/9,
            maskShape: .rectangular,
            cancelPressed: {},
            onCompletion: { img in
                
            }
        )
    }
}
