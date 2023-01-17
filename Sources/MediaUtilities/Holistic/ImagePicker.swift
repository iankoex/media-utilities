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
    var isGuarded: Bool = false
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
        self.isGuarded = isGuarded
        self.onCompletion = onCompletion
    }
    
    @StateObject var dropService: DropDelegateService = .init()
    @State private var dropWasSuccessful: Bool = false
    @State private var pickedOrDroppedImage: UnifiedImage? = nil // Dropped or Picked

    /*
     The Upload logic should be handled in this View then return the link
     the link can then be used at will to update the server.
     */

    public func body(content: Content) -> some View {
        content
            .overlay {
                if pickedOrDroppedImage != nil {
                    ImageEditor(image: $pickedOrDroppedImage, aspectRatio: aspectRatio, onCompletion: onCompletion)
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
            print("dropCompleted Image)")
            withAnimation {
                pickedOrDroppedImage = img
            }
        case .failure(let error):
            print("dropCompleted Error \(error)")
            withAnimation {
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
                    withAnimation {
                        pickedOrDroppedImage = image
                    }
                } else {
                    onCompletion(.failure(MediaUtilitiesError.badImage))
                    print("Failed: Optional Image")
                }
            }
        case let .failure(error):
            onCompletion(.failure(error))
            print("mediaImportComplete Failed: \(error.localizedDescription)")
        }
    }

    private func getImagefromURL(url: URL) async -> UnifiedImage? {
        var data: Data?
        data = try? Data(contentsOf: url, options: .uncached)
        guard let data = data else {
            return nil
        }
        let image: UnifiedImage? = UnifiedImage(data: data)
        return image
    }
}
