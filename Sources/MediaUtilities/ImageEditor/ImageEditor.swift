//
//  ImageEditor.swift
//  
//
//  Created by Ian on 29/12/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
public struct ImageEditor: View {
    @Binding var image: UnifiedImage?
    var aspectRatio: CGFloat
    var onCompletion: (Result<UnifiedImage, Error>) -> Void
    @State private var isExportCompletedSuccessfully: Bool = false
    @State private var isShowingImageCropper: Bool = false

    public var body: some View {
        ZStack {
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
                        cancelPressed: { },
                        onCompletion: { img in
                            self.image = img
                        }
                    )
                    .transition(.opacity)
                }
            } else {
                editorOverlay
            }
        }
        .background(Color.black)
        .transition(.move(edge: .bottom))
    }

    var editorOverlay: some View {
        VStack(alignment: .center) {
            HStack(alignment: .top) {
                cancelButton
                Spacer()
                if isExportCompletedSuccessfully {
                    doneButton
                } else {
                    controlsButtons
                }
            }
            .padding(.top)
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white)
        .padding(.horizontal)
    }

    var cancelButton: some View {
        EditorControlButton(
            isExportCompletedSuccessfully ? "pencil.circle" : "xmark.circle",
            action: cancelButtonActions
        )
    }

    var controlsButtons: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                doneButton
                EditorControlButton("crop", action: showCropImageView)
            }
        }
        .frame(maxWidth: 50)
    }

    var doneButton: some View {
        EditorControlButton("checkmark.circle", action: doneButtonActions)
    }

    private func cancelButtonActions() {
        withAnimation {
            image = nil
        }
    }

    private func doneButtonActions() {

    }

    private func showCropImageView() {
        withAnimation {
            isShowingImageCropper = true
        }
    }
}
