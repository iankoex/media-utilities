//
//  VideoPicker.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI

@available(iOS 15.0, macOS 12, *)
extension View {
    @inlinable public func videoPicker(_ isPresented: Binding<Bool>, onCompletion: @escaping (URL?, Error?) -> Void) -> some View {
        modifier(VideoPicker(isPresented: isPresented, onCompletion: onCompletion))
    }
}

@available(iOS 15.0, macOS 12, *)
public struct VideoPicker: ViewModifier {
    @Binding var isPresented: Bool // Directly Controlls the MediaPicker
    var onCompletion: (URL?, Error?) -> Void

    public init(isPresented: Binding<Bool>, onCompletion: @escaping (URL?, Error?) -> Void) {
        self._isPresented = isPresented
        self.onCompletion = onCompletion
    }
    
    @State private var isActive: Bool = false
    @State private var pickedVideoURL: URL? = nil
    @State private var isShowingVideoTrimmer: Bool = false // will be true if drop was Successful
    @State private var isDropAllowed: Bool = false
    @State private var isDropValidated: Bool = false
    @State private var attempts: CGFloat = 0
    @StateObject private var downloader: VideoDownloader = .init()

    public func body(content: Content) -> some View {
        videoPickerContents(content)
    }

    func videoPickerContents(_ content: Content) -> some View {
        content
            .interactiveDismissDisabled(isPresented)
            .overlay {
                if isActive {
                    overlayContentView
                }
            }
            .overlay {
                if isActive, isDropValidated {
                    dropAllowedView
                }
            }
            .overlay {
                if isShowingVideoTrimmer {
                    successfulDropView
                        .zIndex(1)
                }
            }
            .onDrop(
                of: [.url, .fileURL, .audiovisualContent],
                delegate: VideoDropDelegate(
                    isActive: $isActive,
                    isValidated: $isDropValidated,
                    isAllowed: $isDropAllowed,
                    isGuarded: false,
                    dropCompleted: dropCompleted(_: error:)
                )
            )
            .onChange(of: isDropValidated) { _ in
                if isDropAllowed == false {
                    withAnimation {
                        attempts += 1
                    }
                }
            }
            .mediaPicker(
                isPresented: $isPresented,
                allowedMediaTypes: MediaTypeOptions.videos,
                allowsMultipleSelection: false,
                onCompletion: mediaImportComplete(_:)
            )
    }

    var overlayContentView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
            }
        }
        .background(.ultraThinMaterial)
    }

    var dropAllowedView: some View {
        Group {
            if isDropAllowed {
                Image(systemName: "hand.thumbsup.circle")
            } else {
                Image(systemName: "xmark.circle")
                    .modifier(Shake(animatableData: attempts))
            }
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundColor(.teal)
        .font(.system(size: 100))
        .padding()
    }

    var successfulDropView: some View {
        Group {
            if pickedVideoURL != nil {
                if pickedVideoURL!.isFileURL {
                    VideoEditor(isPresented: $isShowingVideoTrimmer, videoURL: $pickedVideoURL, onCompletion: onCompletion)
                } else {
                    downloadingView
                }
            }
        }
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
                    isShowingVideoTrimmer = false
                    pickedVideoURL = nil
                }
                downloader.cleanUp()
            }) {
                Text("Cancel")
            }
            .padding()
            Spacer()
            HStack {
                Spacer()
            }
        }
        .background(.ultraThinMaterial)
        .task {
            await downloader.downloadVideo(url: pickedVideoURL!)
        }
        .onChange(of: downloader.finalURL) { _ in
            if downloader.finalURL != nil {
                print(downloader.finalURL, "FinalURL")
                pickedVideoURL = downloader.finalURL
                downloader.cleanUp()
            }
        }
    }

    private func dropCompleted(_ url: URL?, error: Error?) {
        guard let url = url, error == nil else {
            withAnimation {
                isShowingVideoTrimmer = false
            }
            onCompletion(url, error)
            return
        }
        print("URL \(url)")
        pickedVideoURL = url
        print("pickedVideoURL \(pickedVideoURL)")
        withAnimation {
            isShowingVideoTrimmer = true
            isActive = false
        }
    }

    private func mediaImportComplete(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            print("mediaImportComplete URL: \(urls.first)")
            pickedVideoURL = urls.first
            withAnimation {
                self.isShowingVideoTrimmer = true
            }
        case let .failure(error):
            onCompletion(nil, error)
            print("mediaImportComplete", error.localizedDescription)
        }
    }
}
