//
//  VideoDropDelegate.swift
//  Items
//
//  Created by Ian on 07/07/2022.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
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
            itemProvider.loadDataRepresentation(forTypeIdentifier: DropDelegateService.urlIndentifier) { data, _ in
                guard let data = data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) else {
                    return
                }
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    dropService.setIsAllowed(to: true)
                } else {
                    dropService.setIsAllowed(to: false)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.audioVisualContentIndentifier) {
            dropService.isAllowed = true
        }
        dropService.isValidated = true
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dropService.isGuarded == false else {
            dropCompleted(.failure(MediaUtilitiesError.isGuarded))
            return false
        }
        guard let itemProvider = info.itemProviders(for: DropDelegateService.audioVisualIdentifiers).first else {
            dropCompleted(.failure(MediaUtilitiesError.lacksConformingTypeIdentifiers))
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.urlIndentifier) {
            Task {
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: DropDelegateService.urlIndentifier, options: nil)
                guard let urlData = nsSecureCoding as? Data else {
                    return
                }
                let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                let asset = AVAsset(url: url)
                if asset.isPlayable {
                    dropCompleted(.success(url))
                } else {
                    dropCompleted(.failure(MediaUtilitiesError.lacksAudioVisualContent))
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(DropDelegateService.audioVisualContentIndentifier) {
            let progress: Progress = itemProvider.loadFileRepresentation(forTypeIdentifier: DropDelegateService.audioVisualContentIndentifier) { url, err in
                guard let url = url, err == nil else {
                    dropCompleted(.failure(err!))
                    return
                }
                MediaPicker.copyContents(of: url) { localURL, error in
                    if let error {
                        dropService.setIsCopying(to: false)
                        dropCompleted(.failure(error))
                        return
                    }
                    guard let localURL else {
                        dropService.setIsCopying(to: false)
                        return
                    }
                    dropService.setIsCopying(to: false)
                    dropCompleted(.success(localURL))
                }
            }
            dropService.setIsCopying(to: true)
            dropService.progress.addChild(progress, withPendingUnitCount: 1)

            // Monitor isCancelled for the case of importing from Photos.app
            dropService.progress.publisher(for: \.isCancelled)
                .filter( { $0 == true })
                .sink { isCancelled in
                    dropCompleted(.failure(MediaUtilitiesError.cancelled))
                }
                .store(in: &subscriptions)
        } else {
            dropCompleted(.failure(MediaUtilitiesError.lacksConformingTypeIdentifiers))
            return false
        }
        dropService.isValidated = false
        return true
    }
}
