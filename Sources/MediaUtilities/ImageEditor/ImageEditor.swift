//
//  ImageEditor.swift
//  
//
//  Created by Ian on 29/12/2022.
//

import SwiftUI

@available(iOS 13.0, macOS 11, *)
public struct ImageEditor: View {
    @State private var image: UnifiedImage
    let aspectRatio: CGFloat
    let maskShape: MaskShape
    let onCompletion: (Result<UnifiedImage, Error>) -> Void
    
    @State private var isShowingImageCropper: Bool = false
    let fallBackImage: UnifiedImage // will be used in the event of reset
    
    var imageHasBeenEdited: Bool {
        image != fallBackImage
    }
    
    public init(
        image: UnifiedImage,
        aspectRatio: CGFloat,
        maskShape: MaskShape,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) {
        self._image = State(initialValue: image)
        self.aspectRatio = aspectRatio
        self.maskShape = maskShape
        self.onCompletion = onCompletion
        self.fallBackImage = image
    }

    public var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
            }
            Image(unifiedImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
            
            editorOverlay
            if isShowingImageCropper {
                CropImageView(
                    inputImage: image,
                    desiredAspectRatio: aspectRatio,
                    maskShape: maskShape,
                    cancelPressed: showCropImageView,
                    onCompletion: imageCropperCompleted(_:)
                )
                .transition(.opacity.animation(.snappy))
            }
        }
        .transition(.move(edge: .bottom).animation(.snappy))
    }

    var editorOverlay: some View {
        VStack(alignment: .center) {
            HStack(alignment: .top) {
                cancelButton
                Spacer()
                controlsButtons
            }
            .padding(.top)
            Spacer()
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white)
        .padding(.horizontal)
    }

    var cancelButton: some View {
        EditorControlButton(
            imageHasBeenEdited ? "pencil.circle" : "xmark.circle",
            action: cancelButtonActions
        )
    }

    var controlsButtons: some View {
        VStack(spacing: 15) {
            doneButton
            EditorControlButton("crop", action: showCropImageView)
            EditorControlButton("rotate.left", action: rotateImage)
        }
    }

    var doneButton: some View {
        EditorControlButton("checkmark.circle", action: doneButtonActions)
    }

    private func cancelButtonActions() {
        if imageHasBeenEdited {
            image = fallBackImage
        } else {
            onCompletion(.failure(MediaUtilitiesError.cancelled))
        }
    }

    private func doneButtonActions() {
        onCompletion(.success(image))
    }

    private func showCropImageView() {
        withAnimation(.snappy) {
            isShowingImageCropper.toggle()
        }
    }

    private func imageCropperCompleted(_ result: Result<UnifiedImage, Error>) {
        switch result {
            case .success(let editedImage):
                image = editedImage
                isShowingImageCropper = false
            case .failure(let error):
                isShowingImageCropper = false
                print(error.localizedDescription)
                // Handle Error
        }
    }
    
    private func rotateImage() {
        do {
            let angle: Measurement<UnitAngle> = Measurement(value: 90, unit: .degrees)
            let rotatedImage = try MediaUtilities.rotateImage(image, angle: angle)
            self.image = rotatedImage
        } catch {
            print(error.localizedDescription)
        }
    }
}
