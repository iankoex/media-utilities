//
//  ImagePicker.swift
//  Items
//
//  Created by Ian on 27/03/2022.
//

import SwiftUI


@available(iOS 14.0, macOS 11, *)
extension View {
    /// an holictic image picker that allows for picking or dropping image to the attached view and editing the image before retuning the final image.
    /// the image editor uses gestures, keep this in mind when attaching this modifier to a sheet, a scrollview or any view with gestures enabled
    /// - Parameters:
    ///   - isPresented: a bool that directly controls the media picker
    ///   - aspectRatio: desired aspect ratio, when the mash shape is curcular this value is ignored in favour of 1
    ///   - maskShape: desired mask shape, when you choose circular the aspect ratio is automatically 1
    ///   - isGuarded: a bool that indicates whether the attched view can accept dropping of images
    ///   - onCompletion: call back with a result of type `Result<UnifiedImage, Error>`
    ///
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
                isGuarded: .constant(isGuarded),
                onCompletion: onCompletion
            )
        )
    }
    
    /// an holictic image picker that allows for picking or dropping image to the attached view and editing the image before retuning the final image.
    /// the image editor uses gestures, keep this in mind when attaching this modifier to a sheet, a scrollview or any view with gestures enabled
    /// - Parameters:
    ///   - isPresented: a bool that directly controls the media picker
    ///   - aspectRatio: desired aspect ratio, when the mash shape is curcular this value is ignored in favour of 1
    ///   - maskShape: desired mask shape, when you choose circular the aspect ratio is automatically 1
    ///   - isGuarded: a bool that indicates whether the attched view can accept dropping of images
    ///   - onCompletion: call back with a result of type `Result<UnifiedImage, Error>`
    ///
    @inlinable public func imagePicker(
        _ isPresented: Binding<Bool>,
        aspectRatio: CGFloat,
        maskShape: MaskShape = .rectangular,
        isGuarded: Binding<Bool>,
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
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker
    @Binding var isGuarded: Bool
    let aspectRatio: CGFloat
    let maskShape: MaskShape
    let onCompletion: (Result<UnifiedImage, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        aspectRatio: CGFloat,
        maskShape: MaskShape,
        isGuarded: Binding<Bool>,
        onCompletion: @escaping (Result<UnifiedImage, Error>) -> Void
    ) {
        self._isPresented = isPresented
        self.aspectRatio = aspectRatio
        self.maskShape = maskShape
        self._isGuarded = isGuarded
        self.onCompletion = onCompletion
        self._dropService = StateObject(wrappedValue: DropDelegateService(isGuarded: isGuarded.wrappedValue))
    }
    
    @StateObject var dropService: DropDelegateService
    @State private var pickedOrDroppedImage: UnifiedImage? = nil // Dropped or Picked

    public func body(content: Content) -> some View {
        content
            .overlay {
                if let pickedOrDroppedImage {
                    ImageEditor(
                        image: pickedOrDroppedImage,
                        aspectRatio: aspectRatio,
                        maskShape: maskShape,
                        onCompletion: { editorResult in
                            self.pickedOrDroppedImage = nil
                            onCompletion(editorResult)
                        }
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
