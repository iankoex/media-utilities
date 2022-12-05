//
//  File.swift
//  
//
//  Created by Ian on 04/12/2022.
//


import AVKit

import SwiftUI





@available(iOS 13.0, macOS 10.15, *)
public struct CustomControlsView: View {
    @EnvironmentObject private var playerVM: PlayerViewModel

    public init() { }

    public var body: some View {
        VStack {
            HStack {
                Button(action: {
                    playerVM.isShowingControls.toggle()
                }, label: {
                    Text("Controls")
                })
                Button(action: {
                    playerVM.allowsPictureInPicturePlayback.toggle()
                }, label: {
                    Text("PIP")
                })
                Button(action: {
                    playerVM.seekForward()
                }, label: {
                    Text("Next")
                })
                Button(action: {
                    playerVM.seekBackward()
                }, label: {
                    Text("Back")
                })
                Button(action: {
                    playerVM.seekTo(10.0)
                }, label: {
                    Text("Seek to 10")
                })
            }
            HStack {
                if playerVM.isPlaying == false {
                    Button(action: {
                        playerVM.play()
                    }, label: {
                        Text("play.circle")
                    })
                } else {
                    Button(action: {
                        playerVM.pause()
                    }, label: {
                        Text("pause.circle")
                    })
                }
            }
        }
        .padding()
    }
}
