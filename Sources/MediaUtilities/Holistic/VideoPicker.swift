//
//  VideoPicker.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
extension View {
    @inlinable public func videoPicker(
        _ isPresented: Binding<Bool>,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View {
        modifier(VideoPicker(isPresented: isPresented, onCompletion: onCompletion))
    }
}

@available(iOS 14.0, macOS 11, *)
public struct VideoPicker: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker
    var onCompletion: (Result<URL, Error>) -> Void

    public init(isPresented: Binding<Bool>, onCompletion: @escaping (Result<URL, Error>) -> Void) {
        self._isPresented = isPresented
        self.onCompletion = onCompletion
    }

    @State private var pickedVideoURL: URL? = nil
    @State private var isShowingVideoEditor: Bool = false // will be true if drop was Successful
    @StateObject private var downloader: VideoDownloader = .init()
    @StateObject private var dropService: DropDelegateService = .init()

    public func body(content: Content) -> some View {
        content
//            .overlay {
//                if dropService.isActive {
//                    backgroundView
//                }
//                if pickedVideoURL != nil, !pickedVideoURL!.isFileURL {
//                    backgroundView
//                }
//            }
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
            if pickedVideoURL != nil {
                if pickedVideoURL!.isFileURL {
                    VideoEditor(isPresented: $isShowingVideoEditor, videoURL: $pickedVideoURL, onCompletion: onCompletion)
                } else {
                    downloadingView
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

    var downloadingView: some View {
        VStack {
            Spacer()
            ProgressView(downloader.progress)
                .progressViewStyle(.circular)
            HStack {
                Text(downloader.downloadedDataSize)
                Text(downloader.totalDataSize)
            }
            Button(action: {
                downloader.cancelDownload()
                withAnimation {
                    isShowingVideoEditor = false
                    pickedVideoURL = nil
                }
                downloader.reset()
            }) {
                Text("Cancel")
            }
            .padding()
            Spacer()
            HStack {
                Spacer()
            }
        }
        .onAppear {
            Task {
                await downloader.downloadVideo(url: pickedVideoURL!)
            }
        }
        .onChange(of: downloader.finalURL) { _ in
            if downloader.finalURL != nil {
                pickedVideoURL = downloader.finalURL
                downloader.reset()
            }
        }
    }

    private func dropCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            print("dropCompleted URL \(url)")
            pickedVideoURL = url
            DispatchQueue.main.async {
                withAnimation {
                    isShowingVideoEditor = true
                    dropService.isActive = false
                }
            }
        case .failure(let err):
            print("dropCompleted Error \(err)")
            withAnimation {
                isShowingVideoEditor = false
            }
        }
    }

    private func mediaImportComplete(_ result: Result<[URL], Error>) {
        switch result {
            case let .success(urls):
                print("mediaImportComplete URL: \(urls.first)")
                DispatchQueue.main.async {
                    pickedVideoURL = urls.first
                    withAnimation {
                        self.isShowingVideoEditor = true
                    }
                }
            case let .failure(error):
                onCompletion(.failure(error))
                print("mediaImportComplete", error.localizedDescription)
        }
    }
}
