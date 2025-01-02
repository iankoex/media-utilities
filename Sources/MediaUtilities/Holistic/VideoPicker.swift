//
//  VideoPicker.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
extension View {
    
    /// an holictic video picker that allows for picking or dropping of videos or url with videos to the attached view
    /// and editing of the video before retuning the url in the local file sytem.
    /// internet urls will be downloaded before editing the video.
    /// - Parameters:
    ///   - isPresented: a bool that directly controls the media picker
    ///   - isGuarded: a bool that indicates whether the attched view can accept dropping of url or video
    ///   - onCompletion: call back with a result of type `Result<URL, Error>`, the url is a local file url
    @inlinable public func videoPicker(
        _ isPresented: Binding<Bool>,
        isGuarded: Bool = false,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        modifier(
            VideoPicker(
                isPresented: isPresented,
                isGuarded: .constant(isGuarded),
                onCompletion: onCompletion
            )
        )
    }
    
    /// an holictic video picker that allows for picking or dropping of videos or url with videos to the attached view
    /// and editing of the video before retuning the url in the local file sytem.
    /// internet urls will be downloaded before editing the video.
    /// - Parameters:
    ///   - isPresented: a bool that directly controls the media picker
    ///   - isGuarded: a bool that indicates whether the attched view can accept dropping of url or video
    ///   - onCompletion: call back with a result of type `Result<URL, Error>`, the url is a local file url
    @inlinable public func videoPicker(
        _ isPresented: Binding<Bool>,
        isGuarded: Binding<Bool>,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        modifier(
            VideoPicker(
                isPresented: isPresented,
                isGuarded: isGuarded,
                onCompletion: onCompletion
            )
        )
    }
}

@available(iOS 14.0, macOS 11, *)
public struct VideoPicker: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker
    @Binding var isGuarded: Bool
    var onCompletion: (Result<URL, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        isGuarded: Binding<Bool>,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self._isPresented = isPresented
        self._isGuarded = isGuarded
        self.onCompletion = onCompletion
        self._dropService = StateObject(wrappedValue: DropDelegateService(isGuarded: isGuarded.wrappedValue))
    }

    @State private var pickedVideoURL: URL? = nil
    @State private var isShowingVideoEditor: Bool = false // will be true if drop was Successful
    @StateObject private var downloader: VideoDownloader = .init()
    @StateObject private var dropService: DropDelegateService

    public func body(content: Content) -> some View {
        content
            .overlay {
                if isShowingVideoEditor {
                    successfulDropView
                        .zIndex(1)
                }
            }
            .overlay {
                if dropService.isCopyingFile {
                    copyingFileView
                }
            }
            .overlay {
                if dropService.isActive, dropService.isValidated {
                    dropAllowedView
                }
            }
            .onDrop(
                of: [.url, .fileURL, .audiovisualContent],
                delegate: VideoDropDelegate(
                    dropService: dropService,
                    dropCompleted: dropCompleted(_:)
                )
            )
            .mediaPicker(
                isPresented: $isPresented,
                allowedMediaTypes: MediaTypeOptions.videos,
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

    var successfulDropView: some View {
        Group {
            if let pickedVideoURL {
                if pickedVideoURL.isFileURL {
                    VideoEditor(isPresented: $isShowingVideoEditor, videoURL: $pickedVideoURL, onCompletion: onCompletion)
                } else {
                    downloadingView(using: pickedVideoURL)
                }
            }
        }
    }

    var copyingFileView: some View {
        VStack {
            Spacer()
            ProgressView(dropService.progress)
                .progressViewStyle(.linear)
                .padding()
            SpinnerView()
            Text("LOADING...")
                .font(.caption)
            Spacer()
            HStack {
                Spacer()
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .transition(.move(edge: .bottom).animation(.snappy))
    }

    func downloadingView(using url: URL) -> some View {
        VStack {
            Spacer()
            ProgressView(downloader.progress)
                .progressViewStyle(.circular)
            HStack {
                Text(downloader.downloadedDataSize)
                Text(downloader.totalDataSize)
            }
            Button("Cancel") {
                downloader.cancelDownload()
                withAnimation {
                    isShowingVideoEditor = false
                    pickedVideoURL = nil
                }
                downloader.reset()
            }
            .padding()
            Spacer()
            HStack {
                Spacer()
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            Task {
                await downloader.downloadVideo(url: url)
            }
        }
        .onChange(of: downloader.finalURL) { downloaderFinalURL in
            if let downloaderFinalURL {
                pickedVideoURL = downloaderFinalURL
                downloader.reset()
            }
        }
    }

    private func dropCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pickedVideoURL = url
            DispatchQueue.main.async {
                withAnimation {
                    isShowingVideoEditor = true
                    dropService.isActive = false
                }
            }
        case .failure(let err):
            withAnimation {
                isShowingVideoEditor = false
            }
        }
    }

    private func mediaImportComplete(_ result: Result<[URL], Error>) {
        switch result {
            case let .success(urls):
                DispatchQueue.main.async {
                    pickedVideoURL = urls.first
                    withAnimation {
                        self.isShowingVideoEditor = true
                    }
                }
            case let .failure(error):
                onCompletion(.failure(error))
        }
    }
}
