//
//  ImageEditor.swift
//  
//
//  Created by Ian on 29/12/2022.
//

import SwiftUI

@available(iOS 13.0, macOS 11, *)
public struct ImageEditor: View {
    @Binding var image: UnifiedImage?
    let aspectRatio: CGFloat
    let maskShape: MaskShape
    let onCompletion: (Result<UnifiedImage, Error>) -> Void
    @State private var imageHasBeenEdited: Bool = false
    @State private var isShowingImageCropper: Bool = false
    @State private var fallBackImage: UnifiedImage? = nil // will be used in the event of reset

    public var body: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
            }
            if let image = image {
                Image(unifiedImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                editorOverlay
                if isShowingImageCropper {
                    CropImageView(
                        $isShowingImageCropper,
                        inputImage: image,
                        desiredAspectRatio: aspectRatio,
                        maskShape: maskShape,
                        cancelPressed: { },
                        onCompletion: imageCropperCompleted(_:)
                    )
                    .transition(.opacity)
                }
            } else {
                editorOverlay
            }
        }
        .transition(.move(edge: .bottom))
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
            withAnimation {
                imageHasBeenEdited = false
            }
        } else {
            withAnimation {
                image = nil
            }
        }
    }

    private func doneButtonActions() {
        withAnimation {
            if let img = image {
                onCompletion(.success(img))
            } else {
                onCompletion(.failure(MediaUtilitiesError.nilImage))
            }
            image = nil
        }
    }

    private func showCropImageView() {
        withAnimation {
            isShowingImageCropper = true
        }
    }

    private func imageCropperCompleted(_ result: Result<UnifiedImage, Error>) {
        fallBackImage = image
        switch result {
            case .success(let editedImage):
                image = editedImage
                withAnimation {
                    imageHasBeenEdited = true
                }
            case .failure(let error):
                print(error.localizedDescription)
                // Handle Error
        }
    }
    
    private func rotateImage() {
        guard let image else { return }
        do {
            let angle: Measurement<UnitAngle> = Measurement(value: -90, unit: .degrees)
            let rotatedImage = try MediaUtilities.rotateImage(image, angle: angle)
            self.image = rotatedImage
            withAnimation {
                imageHasBeenEdited = true
            }
        } catch {
            print(error.localizedDescription)
        }
    }
}
