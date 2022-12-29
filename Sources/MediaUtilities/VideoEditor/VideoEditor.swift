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
    var onCompletion: (URL?, Error?) -> Void

    // onCompletions for done and cancel buttons
    // before done set the statusBar to default
    //    @Environment(\.scenePhase) var scenePhase
    @StateObject private var videoUtil: VideoUtil = VideoUtil()
    @StateObject private var playerVM = PlayerViewModel()

    @State private var isShowingControlButtonNames: Bool = false
    @State private var isShowingSlider: Bool = false
    
    @State private var isExporting = false
    @State private var isExportCompletedSuccessfully: Bool = false {
        didSet { playerVM.isShowingControls = isExportCompletedSuccessfully }
    }
    @State private var exportedVideoURL: URL? = nil

    public init(isPresented: Binding<Bool>, videoURL: Binding<URL?>, onCompletion: @escaping (URL?, Error?) -> Void) {
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
        .background(Color.black)
        .transition(.move(edge: .bottom))
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
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .padding(.horizontal)
    }

    var cancelButton: some View {
        Button(action: cancelButtonActions) {
            if isExportCompletedSuccessfully {
                Text("Edit")
            } else {
                Image(systemName: "xmark.circle")
                    .font(.title2)
                    .grayBackgroundCircle()
            }
        }
    }

    var controlsButtons: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 15) {
                doneButton
                controlButton(audioControlImage) {
                    withAnimation {
                        playerVM.isMuted ? playerVM.unmute() : playerVM.mute()
                    }
                }
                controlButton("timeline.selection") {
                    withAnimation {
                        isShowingSlider.toggle()
                    }
                }
            }
        }
        .frame(maxWidth: 50)
    }

    var doneButton: some View {
        controlButton("checkmark.circle", action: doneButtonActions)
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
                Button(action: {
                    videoUtil.exporter?.cancelExport()
                    withAnimation {
                        isExporting = false
                    }
                }) {
                    Text("Cancel")
                }
                .padding()
            }
            .navigationTitle("Exporting Video...")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func controlButton(_ image: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: action) {
                HStack(spacing: 0) {
                    Spacer(minLength: 1)
                    Image(systemName: image)
                        .font(.title2)
                        .padding(2)
                        .grayBackgroundCircle()
                    Spacer(minLength: 1)
                }
                .frame(maxWidth: 50)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.white)
        }
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
            onCompletion(exportedVideoURL, nil)
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
                withAnimation {
                    isExporting = true
                }
                videoUtil.trim(
                    from: playerVM.startPlayingAt,
                    to: playerVM.endPlayingAt,
                    with: .presetHighestQuality,
                    onCompletion: exportCompleted(_:)
                )
            }
        }
    }

    private func exportCompleted(_ result: VideoUtil.Result) {
        switch result {
        case let .success(successURL):
            exportedVideoURL = successURL
            playerVM.setCurrentItem(exportedVideoURL!)
            withAnimation {
                isExporting = false
                isExportCompletedSuccessfully = true
            }
            print("Trim was a success")

        case let .error(error):
            withAnimation {
                isExporting = false
            }
            onCompletion(nil, error)
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
