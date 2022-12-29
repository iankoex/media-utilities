//
//  VideoDropDelegate.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
//import AVKit
import Combine

/*
  The use of AVAsset here is to enable the drag and drop
 of internet URLs (not Local URL) that dont have .mp4 or audioVisual
 conforming pathExtension.
 */

@available(iOS 13.4, macOS 10.15, *)
struct VideoDropDelegate: DropDelegate {
    @ObservedObject var dropService: DropDelegateService
    var dropCompleted: (Result<URL, Error>) -> Void
    @State private var subscriptions: Set<AnyCancellable> = []

    func dropEntered(info: DropInfo) {
        withAnimation {
            dropService.isActive = true
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation {
            dropService.isActive = false
            dropService.isValidated = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard dropService.isGuarded == false else {
            return false
        }
        guard let itemProvider = info.itemProviders(for: DropDelegateService.audioVisualIdentifiers).first else {
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.urlIndentifier) {
            print("has url")

            itemProvider.loadDataRepresentation(forTypeIdentifier: DropDelegateService.urlIndentifier) { data, _ in
                guard let data = data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) else {
                    print("ER")
                    return
                }
                print("URL", url)
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    print("Conforms")
                    dropService.setIsAllowed(to: true)
                } else {
                    print("Does Not CONFORM")
                    dropService.setIsAllowed(to: false)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.audioVisualContentIndentifier) {
            print("Has audsio visual")
            dropService.isAllowed = true
        }
        dropService.isValidated = true
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dropService.isGuarded == false else {
            dropCompleted(.failure(DropDelegateError.isGuarded))
            return false
        }
//        guard isAllowed else {
//            return false
//        }
        guard let itemProvider = info.itemProviders(for: DropDelegateService.audioVisualIdentifiers).first else {
            dropCompleted(.failure(DropDelegateError.lacksConformingTypeIdentifiers))
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.urlIndentifier) {
            Task {
                #if os(iOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: DropDelegateService.urlIndentifier, options: nil)
                if let urlData = nsSecureCoding as? Data {
                    let str = try? JSONDecoder().decode(URL.self, from: urlData)
                    print(str, "URLLLL")
                }
                #endif
                #if os(macOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: DropDelegateService.urlIndentifier, options: nil)
                guard let urlData = nsSecureCoding as? Data else {
                    return
                }
                let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                print(url, "URLLLL")
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    dropCompleted(.success(url))
                } else {
                    dropCompleted(.failure(DropDelegateError.lacksAudioVisualContent))
                }
                #endif
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.audioVisualContentIndentifier) {
            print("audiovisualContentaudiovisualContent")
            let progress: Progress = itemProvider.loadFileRepresentation(forTypeIdentifier: DropDelegateService.audioVisualContentIndentifier) { url, err in
                guard let url = url, err == nil else {
                    dropCompleted(.failure(err!))
                    return
                }
                MediaPicker.copyContents(of: url) { localURL, error in
                    guard let localURL = localURL, error == nil else {
                        dropService.setIsCopying(to: false)
                        dropCompleted(.failure(error!))
                        return
                    }
                    print("localURl", localURL)
                    dropService.setIsCopying(to: false)
                    dropCompleted(.success(localURL))
                }
            }
            dropService.setIsCopying(to: true)
            dropService.progress.addChild(progress, withPendingUnitCount: 1)

            // Monitor isCancelled for the case of importing from Photos.app
            dropService.progress.publisher(for: \.fractionCompleted)
                .sink { fractionCompleted in
                    print("fractionCompleted", fractionCompleted)
                }
                .store(in: &subscriptions)
            dropService.progress.publisher(for: \.isCancelled)
                .filter( { $0 == true })
                .sink { isCancelled in
                    print("isCancelled", isCancelled)
                }
                .store(in: &subscriptions)
        } else {
            dropCompleted(.failure(DropDelegateError.lacksConformingTypeIdentifiers))
            return false
        }
        dropService.isValidated = false
        return true
    }
}

/*
 itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.audiovisualContent.identifier) { url, err in
     guard let url = url, err == nil else {
         print("we Found Errors")
         return
     }
     print(url, "::::")
     let asset = AVAsset(url: url)
     if asset.isPlayable {
         print("Conforms")
         dropService.setIsAllowed(to: true)
     } else {
         print("Does Not CONFORM")
         dropService.setIsAllowed(to: false)
     }
 }
 */
