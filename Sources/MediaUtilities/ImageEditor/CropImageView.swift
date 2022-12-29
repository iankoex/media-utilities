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
struct CropImageView: View {
    @Binding var isPresented: Bool
    var inputImage: UnifiedImage
    @Binding var croppedImage: UnifiedImage?
    var desiredAspectRatio: CGFloat
    var cancelPressed: () -> Void

    @State private var selectedAspectRatio: CGFloat = 0.0
    @State private var displayWidth: CGFloat = 0.0
    @State private var displayWeight: CGFloat = 0.0
    @State private var screenSize: CGSize = .zero
    @State private var screenAspect: CGFloat = 0.0
    let inset: CGFloat = 15
   
    //Zoom Scale and Drag...
    @State private var currentAmount: CGFloat = 0
    @State private var finalAmount: CGFloat = 1
    @State private var currentPosition: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0.0
    @State private var verticalOffset: CGFloat = 0.0
    
    init(
        isPresented: Binding<Bool>,
        inputImage: UnifiedImage,
        croppedImage: Binding<UnifiedImage?>,
        desiredAspectRatio: CGFloat,
        cancelPressed: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.inputImage = inputImage
        self._croppedImage = croppedImage
        self.desiredAspectRatio = 1 / desiredAspectRatio
        self.cancelPressed = cancelPressed
    }
    
    var body: some View {
        GeometryReader { proxy in
            contents
                .onAppear {
                    setScreenParticulars(proxy.size)
                }
                .onChange(of: proxy.size, perform: setScreenParticulars(_:))
        }
        #if os(macOS)
        .frame(width: 700 * 3 / 4, height: 700)
        .aspectRatio(3 / 4, contentMode: .fit)
        #endif
    }
    
    var contents: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Image(unifiedImage: inputImage)
                    .resizable()
                    .scaleEffect(finalAmount + currentAmount)
                    .scaledToFill()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: screenSize.width, height: screenSize.height, alignment: .center)
                    .offset(x: self.currentPosition.width, y: self.currentPosition.height)
                    .clipped()
            }

            Rectangle()
                .fill(Color.black.opacity(0.3))
                .mask(
                    HoleShapeMask(screenSize: screenSize)
                        .fill(style: FillStyle(eoFill: true))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                Text("Move and Scale")
                    .foregroundColor(.white)
                    .padding(20)
                Spacer()
                bottomButtons
                    .background(Color.red)
            }
        }
        .gesture(magGesture)
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(tapGesture)
    }
    
    var bottomButtons: some View {
        HStack {
            Button(action: {
                isPresented = false
                cancelPressed()
            }) {
                Text("Cancel")
            }
            .buttonStyle(.bordered)
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
            Spacer()
            #endif
            Button(action: {
                cropImage(screenSize)
            }) {
                Text("Done")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
    }
    
    var magGesture: some Gesture {
        MagnificationGesture()
            .onChanged { amount in
                self.currentAmount = amount - 1
            }
            .onEnded { amount in
                self.finalAmount += self.currentAmount
                self.currentAmount = 0
                repositionImage(screenSize: screenSize)
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                self.currentPosition = CGSize(width: value.translation.width + self.newPosition.width, height: value.translation.height + self.newPosition.height)
            }
            .onEnded { value in
                self.currentPosition = CGSize(width: value.translation.width + self.newPosition.width, height: value.translation.height + self.newPosition.height)
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
        screenAspect = size.width / size.height
        let w = inputImage.size.width
        let h = inputImage.size.height
        selectedAspectRatio = w / h
        resetImageOriginAndScale(screenSize: screenSize)
    }
    
    func HoleShapeMask(screenSize: CGSize) -> Path {
        let rect = CGRect(x: 0, y: 0, width: screenSize.width, height: screenSize.height)
        let oneSideW = rect.maxX - (inset * 2)
        let oneSideH = oneSideW * desiredAspectRatio
        let halfSideX = oneSideW / 2
        let halfSideY = oneSideH / 2
        let insetRect = CGRect(x: (rect.maxX / 2) - halfSideX, y: (rect.maxY / 2) - halfSideY, width: oneSideW, height: oneSideH)
        var shape = Rectangle().path(in: rect)
        shape.addPath(RoundedRectangle(cornerRadius: 10).path(in: insetRect))
        return shape
    }
    
    private func resetImageOriginAndScale(screenSize: CGSize) {
        withAnimation(.easeInOut){
            if selectedAspectRatio > screenAspect {
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
        
        if selectedAspectRatio > screenAspect {
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
        
        if displayWidth < screenSize.width && selectedAspectRatio > screenAspect {
            resetImageOriginAndScale(screenSize: screenSize)
        }
        if displayWeight < screenSize.height && selectedAspectRatio < screenAspect {
            resetImageOriginAndScale(screenSize: screenSize)
        }
    }

    private func cropImage(_ screenSize: CGSize) {
        let scale = (inputImage.size.width) / displayWidth
        let xPos = ( ( ( displayWidth - screenSize.width ) / 2 ) + inset + ( currentPosition.width * -1 ) ) * scale
        let yPos = ( ( ( displayWeight - (screenSize.width * desiredAspectRatio) ) / 2  ) + inset + ( currentPosition.height * -1 ) ) * scale
        let radius = ( screenSize.width - inset * 2 ) * scale
        let radius1 = radius * desiredAspectRatio
        croppedImage = imageFromCrop(image: inputImage, croppedTo: CGRect(x: xPos, y: yPos, width: radius, height: radius1))
        isPresented = false
    }
    
    #if os(iOS)
    private func imageFromCrop(image: UIImage, croppedTo rect: CGRect) -> UIImage {
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        let drawRect = CGRect(x: -rect.origin.x, y: -rect.origin.y, width: image.size.width, height: image.size.height)
        context?.clip(to: CGRect(x: 0, y: 0, width: rect.size.width, height: rect.size.height))
        image.draw(in: drawRect)
        let subImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return subImage!
     }
    #else

    private func imageFromCrop(image: NSImage, croppedTo rect: CGRect) -> NSImage {
        let croppedImrect: CGRect = rect
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        var croppedImage = NSImage(named: "iconWhite")
        if let cropped = cgImage!.cropping(to: croppedImrect) {
            croppedImage = NSImage(cgImage: cropped, size: rect.size)
        }
        return croppedImage!
    }
    #endif
}

@available(iOS 14.0, macOS 11, *)
struct Cropr_Previews: PreviewProvider {
    static var previews: some View {
        CropImageView(isPresented: .constant(true), inputImage: UnifiedImage(named: "mac")!, croppedImage: .constant(nil), desiredAspectRatio: 16/9, cancelPressed: {})
    }
}
