//
//  VideoTrimmer.swift
//  Items
//
//  Created by Ian on 23/06/2022.
//

import SwiftUI

@available(iOS 14.0, macOS 11, *)
public struct VideoEditor: View {
    @Binding var isPresented: Bool
    @Binding var videoURL: URL?
    let onCompletion: (Result<URL, Error>) -> Void
    
    @StateObject private var videoUtil: VideoUtil = VideoUtil()
    @StateObject private var playerVM = PlayerViewModel()
    
    @State private var isShowingControlButtonNames: Bool = false
    @State private var isShowingSlider: Bool = false
    
    @State private var isExporting = false
    @State private var isExportCompletedSuccessfully: Bool = false {
        didSet { playerVM.isShowingControls = isExportCompletedSuccessfully }
    }
    @State private var exportedVideoURL: URL? = nil
    
    public init(
        isPresented: Binding<Bool>,
        videoURL: Binding<URL?>,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self._isPresented = isPresented
        self._videoURL = videoURL
        self.onCompletion = onCompletion
    }
    
    public var body: some View {
        ZStack {
            if videoURL != nil {
                videoPlayer
            } else {
                SpinnerView()
            }
            videoOverlay
        }
        .background(Color.black.ignoresSafeArea(.all))
        .transition(.move(edge: .bottom).animation(.snappy))
        .overlay {
            if isExporting {
                exportingOverlay
            }
        }
        .onAppear(perform: initialiseOrResetEditor)
        .onDisappear {
            playerVM.pause()
        }
        .environmentObject(videoUtil)
        .environmentObject(playerVM)
        .onChange(of: videoURL) { newValue in
            initialiseOrResetEditor()
        }
    }
    
    var videoPlayer: some View {
        Group {
            if isExportCompletedSuccessfully {
                CustomVideoPlayer()
                    .padding(.top)
            } else {
                CustomVideoPlayer()
            }
        }
    }
    
    var videoOverlay: some View {
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
            Spacer()
            if isShowingSlider && !isExportCompletedSuccessfully {
                VideoSliderView()
                    .background(Color.gray.opacity(0.001)) // somehow fixes slider issue
                    .padding(.horizontal)
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(.white)
    }
    
    var cancelButton: some View {
        EditorControlButton(
            isExportCompletedSuccessfully ? "pencil.circle" : "xmark.circle",
            action: cancelButtonActions
        )
        .padding(.leading)
    }
    
    var controlsButtons: some View {
        VStack(alignment: .center, spacing: 15) {
            doneButton
            EditorControlButton(audioControlImage) {
                withAnimation {
                    playerVM.isMuted ? playerVM.unmute() : playerVM.mute()
                }
            }
            EditorControlButton("timeline.selection") {
                withAnimation {
                    isShowingSlider.toggle()
                }
            }
        }
        .frame(maxWidth: 60)
    }
    
    var doneButton: some View {
        EditorControlButton("checkmark.circle", action: doneButtonActions)
    }
    
    var audioControlImage: String {
        playerVM.isMuted ? "speaker" : "speaker.slash"
    }
    
    var exportingOverlay: some View {
        NavigationView {
            VStack {
#if os(macOS)
                Text("Exporting Video...")
                    .font(.title)
                    .padding()
#endif
                ProgressView(value: videoUtil.progress)
                    .progressViewStyle(.linear)
                    .padding()
                Button(action: cancelExport) {
                    Text("Cancel")
                }
                .padding()
            }
            .navigationTitle("Exporting Video...")
        }
        .transition(.move(edge: .bottom).animation(.snappy))
    }
    
    private func cancelButtonActions() {
        withAnimation {
            if isExportCompletedSuccessfully {
                initialiseOrResetEditor()
            } else {
                // delete from storage
                playerVM.pause()
                isPresented = false
                videoURL = nil
                isPresented = false
                videoURL = nil
                MediaPicker.cleanDirectory()
                VideoUtil.cleanDirectory()
            }
        }
    }
    
    private func doneButtonActions() {
        if isExportCompletedSuccessfully {
            guard let exportedVideoURL = exportedVideoURL else {
                onCompletion(.failure(MediaUtilitiesError.badImage))
                return
            }
            onCompletion(.success(exportedVideoURL))
            withAnimation {
                isPresented = false
            }
            // set isPresented to false
        } else {
            if playerVM.startPlayingAt == 0, playerVM.endPlayingAt == playerVM.duration {
                // dont export anything
                exportedVideoURL = videoURL
                withAnimation {
                    isExportCompletedSuccessfully = true
                }
            } else {
                playerVM.pause()
                withAnimation {
                    isExporting = true
                }
                videoUtil.trim(
                    from: playerVM.startPlayingAt,
                    to: playerVM.endPlayingAt,
                    with: .presetHighestQuality,
                    removeAudio: playerVM.isMuted,
                    onCompletion: exportCompleted(_:)
                )
            }
        }
    }
    
    private func exportCompleted(_ result: Result<URL, VideoUtil.VideoUtilError>) {
        switch result {
            case let .success(successURL):
                exportedVideoURL = successURL
                playerVM.setCurrentItem(exportedVideoURL!)
                withAnimation {
                    isExporting = false
                    isExportCompletedSuccessfully = true
                }
                playerVM.startPlayingAt = .zero
                playerVM.play()
                
            case let .failure(error):
                withAnimation {
                    isExporting = false
                }
                onCompletion(.failure(error))
        }
    }
    
    private func cancelExport() {
        videoUtil.exporter?.cancelExport()
        playerVM.play()
        withAnimation {
            isExporting = false
        }
    }
    
    private func initialiseOrResetEditor() {
        isExportCompletedSuccessfully = false
        isShowingSlider = false
        playerVM.isShowingControls = false
        playerVM.currentTime = .zero
        playerVM.startPlayingAt = .zero
        playerVM.endPlayingAt = .zero
        guard let videoURL = videoURL else {
            return
        }
        if videoUtil.videoURL != videoURL {
            videoUtil.videoURL = videoURL
        }
        playerVM.setCurrentItem(videoURL)
        playerVM.play()
    }
}
