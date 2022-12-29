//
//  ImagePicker.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
extension View {
    @inlinable public func imagePicker(_ isPresented: Binding<Bool>, aspectRatio: CGFloat, isGuarded: Bool, onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void) -> some View {
        modifier(ImagePicker(isPresented: isPresented, aspectRatio: aspectRatio, isGuarded: isGuarded, onCompletion: onCompletion))
    }
}

@available(iOS 14.0, macOS 11, *)
public struct ImagePicker: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker

    var aspectRatio: CGFloat
    var onCompletion: (Result<UnifiedImage, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        aspectRatio: CGFloat,
        isGuarded: Bool,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) {
        self._isPresented = isPresented
        self.aspectRatio = aspectRatio
//        isGuarded
        self.onCompletion = onCompletion
    }

    @StateObject private var dropService: DropDelegateService = .init()

   var finalImage: UnifiedImage? = nil



    @State private var dropWasSuccessful: Bool = false

    @State private var firstImage: UnifiedImage? = nil // Dropped or Picked
    @State private var isCropperShown: Bool = false
    @State private var croppedImage: UnifiedImage? = nil
    @State private var imageUrlInStorage: URL? = nil
    @State private var isShowingMediaPicker = false

    /*
     The Upload logic should be handled in this View then return the link
     the link can then be used at will to update the server.
     */

    public func body(content: Content) -> some View {
        imagePickerContents(content)
//        if hSizeClass == .regular {
//            imagePickerContents(content)
//                .sheet(isPresented: $isCropperShown, onDismiss: {
//                    if let croppedImage = croppedImage {
//                        shownImage = croppedImage
//                    }
//                }) {
//                    CropImageView(isPresented: $isCropperShown, inputImage: firstImage ?? shownImage, croppedImage: $croppedImage, desiredAspectRatio: aspectRatio, cancelPressed: {
//                        print("Cancelled")
//                    })
////                    .interactiveDismissDisabled(true)
//                }
//        } else {
//            imagePickerContents(content)
//            #if os(iOS)
//                .fullScreenCover(isPresented: $isCropperShown, onDismiss: {
//                    if let croppedImage = croppedImage {
//                        shownImage = croppedImage
//                    }
//                }) {
//                    CropImageView(isPresented: $isCropperShown, inputImage: firstImage ?? shownImage, croppedImage: $croppedImage, desiredAspectRatio: aspectRatio, cancelPressed: {
//                        print("Cancelled")
//                    })
//                }
//            #endif
//        }
    }

    func imagePickerContents(_ content: Content) -> some View {
        content
            .overlay {
                if firstImage != nil {
                    ImageEditor(image: $firstImage, aspectRatio: aspectRatio) { result in

                    }
                }
            }
            .overlay {
                if dropService.isActive, dropService.isValidated {
                    dropAllowedView
                }
            }
            .onDrop(
                of: [.url, .fileURL, .image],
                delegate: ImageDropDelegate(
                    dropService: dropService,
                    dropCompleted: dropCompleted(_:)
                )
            )
            .mediaPicker(
                isPresented: $isPresented,
                allowedMediaTypes: MediaTypeOptions.images,
                allowsMultipleSelection: false,
                onCompletion: mediaImportComplete(_:)
            )
    }

    var dropAllowedView: some View {
        Group {
            if dropService.isAllowed {
                Image(systemName: "hand.thumbsup.circle")
            } else {
                Image(systemName: "xmark.circle")
                    .modifier(Shake(animatableData: dropService.attempts))
            }
        }
        .foregroundColor(dropService.isAllowed ? .accentColor : .red)
        .font(.system(size: 50))
        .grayBackgroundCircle()
    }

    private func dropCompleted(_ result: Result<UnifiedImage, Error>) {
        switch result {
        case .success(let img):
            print("dropCompleted Image)")
            firstImage = img
        case .failure(let err):
            print("dropCompleted Error \(err)")
            withAnimation {
                dropWasSuccessful = false
            }
            print("Failed")
        }
    }

    private func mediaImportComplete(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):

            imageUrlInStorage = urls[0]
            Task {
                let image = await getImagefromURL(url: urls[0])
                if let image = image {
                    firstImage = image
                } else {
                    print("Failed: Optional Image")
                }
            }
        case let .failure(error):
            print(error)
            imageUrlInStorage = nil
            print("Failed: \(error.localizedDescription)")
        }
    }

    private func getImagefromURL(url: URL) async -> UnifiedImage? {
        var data: Data?
        do {
            data = try Data(contentsOf: url, options: .uncached)
        } catch {
            print("UnifiedImage Data Sth")
        }
        guard let data = data else {
            return nil
        }
        let image: UnifiedImage? = UnifiedImage(data: data)
        return image
    }
}
