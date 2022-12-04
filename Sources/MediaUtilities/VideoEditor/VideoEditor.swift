//
//  VideoTrimmer.swift
//  Items
//
//  Created by Ian on 23/06/2022.
//

import SwiftUI

@available(iOS 15.0, macOS 12, *)
public struct VideoEditor: View {
    @Binding var isPresented: Bool
    @Binding var videoURL: URL?
    @Binding var finalVideoURL: URL?

    // callbacks for done and cancel buttons
    // before done set the statusBar to default
    //    @Environment(\.scenePhase) var scenePhase
    @StateObject private var videoUtil: VideoUtil = .init()

    @State private var isShowingControlButtonNames: Bool = false
    @State private var isShowingSlider: Bool = false
    
    @State private var isExporting = false
    @State private var isExportCompletedSuccessfully: Bool = false {
        didSet { playerVM.isShowingControls = isExportCompletedSuccessfully }
    }
    @State private var exportedVideoURL: URL? = nil
    // The least seconds should be 10 seconds
    // create a offset value for 5 seconds and makesure offset are not less than that
    @StateObject private var playerVM = PlayerViewModel()

    public init(isPresented: Binding<Bool>, videoURL: Binding<URL?>, finalVideoURL: Binding<URL?>) {
        self._isPresented = isPresented
        self._videoURL = videoURL
        self._finalVideoURL = finalVideoURL
    }

    var convinienceVideoURL: URL {
        if isExportCompletedSuccessfully {
            return exportedVideoURL ?? videoURL!
        } else {
            return videoURL!
        }
    }

    public var body: some View {
        ZStack {
            if videoURL != nil {
                CustomVideoPlayer()
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
        .onAppear {
            videoUtil.videoURL = videoURL
            playerVM.isShowingControls = false
            playerVM.setCurrentItem(videoURL!)
            playerVM.play()
        }
        .onDisappear {
            playerVM.pause()
        }
        .environmentObject(videoUtil)
        .environmentObject(playerVM)
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
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.largeTitle)
            }
        }
    }

    var controlsButtons: some View {
        VStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    doneButton
                    controlButton(audioControlTitle, image: audioControlImage) {
                        withAnimation {
                            playerVM.isMuted.toggle()
                        }
                    }
                    controlButton("Trim", image: "timeline.selection") {
                        withAnimation {
                            isShowingSlider.toggle()
                        }
                    }
                }
            }
            Spacer()
        }
    }

    var doneButton: some View {
        controlButton("Done", image: "checkmark.circle.fill", action: doneButtonActions)
    }

    var audioControlTitle: String {
        "Audio \(playerVM.isMuted ? "on" : "off")"
    }

    var audioControlImage: String {
        playerVM.isMuted ? "speaker.circle" : "speaker.slash.circle"
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

    private func cancelButtonActions() {
        withAnimation {
            if isExportCompletedSuccessfully {
                // revert to editing view
                isExportCompletedSuccessfully = false
                //                startOffset = 0
                //                seekerOffset = 0
                //                endOffset = 0
            } else {
                // delete from storage
                isPresented = false
                videoURL = nil
                isPresented = false
                videoURL = nil
//                MediaPicker.cleanDirectory()
                VideoUtil.cleanDirectory()
            }
        }
    }

    private func doneButtonActions() {
        if isExportCompletedSuccessfully {
            finalVideoURL = exportedVideoURL
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
                    callback: exportCompleted(_:)
                )
            }
        }
    }

    private func controlButton(_ name: String, image: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: action) {
                HStack {
                    if isShowingControlButtonNames {
                        Text(name)
                    }
                    HStack(spacing: 0) {
                        Spacer(minLength: 1)
                        Image(systemName: image)
                            .symbolRenderingMode(.hierarchical)
                            .font(.largeTitle)
                        Spacer(minLength: 1)
                    }
                    .frame(maxWidth: 50)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
        }
    }

    private func exportCompleted(_ result: VideoUtil.Result) {
        switch result {
        case let .success(successURL):
            exportedVideoURL = successURL
            withAnimation {
                isExporting = false
                isExportCompletedSuccessfully = true
            }
            print("Trim was a success")

        case let .error(error):
            withAnimation {
                isExporting = false
            }
            print(error)
        }
    }
}
