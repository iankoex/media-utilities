//
//  ImagePicker.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
extension View {
    @inlinable public func imagePicker(
        _ isPresented: Binding<Bool>,
        aspectRatio: CGFloat,
        maskShape: MaskShape = .rectangular,
        isGuarded: Bool = false,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) -> some View {
        modifier(
            ImagePicker(
                isPresented: isPresented,
                aspectRatio: aspectRatio,
                maskShape: maskShape,
                isGuarded: isGuarded,
                onCompletion: onCompletion
            )
        )
    }
}

@available(iOS 14.0, macOS 11, *)
public struct ImagePicker: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker
    let isGuarded: Bool
    let aspectRatio: CGFloat
    let maskShape: MaskShape
    let onCompletion: (Result<UnifiedImage, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        aspectRatio: CGFloat,
        maskShape: MaskShape,
        isGuarded: Bool,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) {
        self._isPresented = isPresented
        self.aspectRatio = aspectRatio
        self.maskShape = maskShape
        self.isGuarded = isGuarded
        self.onCompletion = onCompletion
    }
    
    @StateObject var dropService: DropDelegateService = .init()
    @State private var dropWasSuccessful: Bool = false
    @State private var pickedOrDroppedImage: UnifiedImage? = nil // Dropped or Picked

    public func body(content: Content) -> some View {
        content
            .overlay {
                if pickedOrDroppedImage != nil {
                    ImageEditor(
                        image: $pickedOrDroppedImage,
                        aspectRatio: aspectRatio,
                        maskShape: maskShape,
                        onCompletion: onCompletion
                    )
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
            .onChange(of: isGuarded) { bool in
                dropService.isGuarded = bool
            }
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
                withAnimation(.snappy) {
                    pickedOrDroppedImage = img
                }
            case .failure(let error):
                withAnimation(.snappy) {
                    dropWasSuccessful = false
                }
                onCompletion(.failure(error))
        }
    }

    private func mediaImportComplete(_ result: Result<[URL], Error>) {
        switch result {
            case let .success(urls):
                Task {
                    let image = await getImagefromURL(url: urls[0])
                    if let image = image {
                        withAnimation(.snappy) {
                            pickedOrDroppedImage = image
                        }
                    } else {
                        onCompletion(.failure(MediaUtilitiesError.failedToGetImageFromURL))
                    }
                }
            case let .failure(error):
                onCompletion(.failure(MediaUtilitiesError.importImageError(error.localizedDescription)))
        }
    }

    private func getImagefromURL(url: URL) async -> UnifiedImage? {
        guard let data = try? Data(contentsOf: url, options: .uncached) else {
            return nil
        }
        return UnifiedImage(data: data)
    }
}
