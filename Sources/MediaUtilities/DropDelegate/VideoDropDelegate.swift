//
//  VideoDropDelegate.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AVKit

/*
  The use of AVAsset here is to enable the drag and drop
 of internet URLs (not Local URL) that dont have .mp4 or audioVisual
 conforming pathExtension.
 */

@available(iOS 14.0, macOS 11, *)
struct VideoDropDelegate: DropDelegate {
    @Binding var isActive: Bool
    @Binding var isValidated: Bool
    @Binding var isAllowed: Bool
    var isGuarded: Bool
    var dropCompleted: (URL?, Error?) -> Void

    func dropEntered(info: DropInfo) {
        withAnimation {
            isActive = true
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation {
            isActive = false
            isValidated = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard isGuarded == false else {
            dropCompleted(nil, DropDelegateError.isGuarded)
            return false
        }
        guard let itemProvider = info.itemProviders(for: [.audiovisualContent, .url, .fileURL]).first else {
            dropCompleted(nil, DropDelegateError.lacksConformingTypeIdentifiers)
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            print("has url")

            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                guard let data = data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) else {
                    print("ER")
                    return
                }
                print("URL", url)
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    print("Conforms")
                    isAllowed = true
                } else {
                    print("Does Not CONFORM")
                    isAllowed = false
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.audiovisualContent.identifier) {
            print("Has audsio visual")

            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.audiovisualContent.identifier) { url, err in
                guard let url = url, err == nil else {
                    print("we Found Errors")
                    return
                }
                print(url, "::::")
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    print("Conforms")
                    isAllowed = true
                } else {
                    print("Does Not CONFORM")
                    isAllowed = false
                }
            }
        }
        isValidated = true
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isGuarded == false else {
            dropCompleted(nil, DropDelegateError.isGuarded)
            return false
        }
//        guard isAllowed else {
//            return false
//        }
        guard let itemProvider = info.itemProviders(for: [.audiovisualContent, .url, .fileURL]).first else {
            dropCompleted(nil, DropDelegateError.lacksConformingTypeIdentifiers)
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            Task {
                #if os(iOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
                if let urlData = nsSecureCoding as? Data {
                    let str = try? JSONDecoder().decode(URL.self, from: urlData)
                    print(str, "URLLLL")
                }
                #endif
                #if os(macOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
                guard let urlData = nsSecureCoding as? Data else {
                    return
                }
                let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                print(url, "URLLLL")
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    dropCompleted(url, nil)
                } else {
                    dropCompleted(url, DropDelegateError.lacksAudioVisualContent)
                }
                #endif
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.audiovisualContent.identifier) {
            print("audiovisualContentaudiovisualContent")
            itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.audiovisualContent.identifier) { url, err in
                guard let url = url, err == nil else {
                    print("we Foudn Errord")
                    return
                }
                print(url, "::::")
                MediaPicker.copyContents(of: url) { localURL, error in
                    guard let localURL = localURL, error == nil else {
                        print("Error Copying")
                        dropCompleted(localURL, error)
                        return
                    }
                    print("localURl", localURL)
                    dropCompleted(localURL, nil)
                }
            }
        } else {
            dropCompleted(nil, DropDelegateError.lacksConformingTypeIdentifiers)
            return false
        }
        isValidated = false
        return true
    }
}
