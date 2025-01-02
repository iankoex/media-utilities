//
//  ImageDropDelegate.swift
//  Items
//
//  Created by Ian on 29/03/2022.
//

import SwiftUI
import UniformTypeIdentifiers

@available(iOS 14.0, macOS 11, *)
struct ImageDropDelegate: DropDelegate {
    @ObservedObject var dropService: DropDelegateService
    var dropCompleted: (Result<UnifiedImage, Error>) -> Void

    func dropEntered(info: DropInfo) {
        withAnimation {
            dropService.isActive = true
            // reset the helpers
            dropService.temporaryImage = nil
            dropService.anItemWasDropped = false
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
        guard let itemProvider = info.itemProviders(for: [.image, .url, .fileURL]).first else {
            return false
        }
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                // blocks dragging image from Safari in iOS 
                guard let data = data, let path = NSString(data: data, encoding: 4), let url = URL(string: path as String) else {
                    return
                }
                guard let typeID = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier else {
                    return
                }
                guard let utType = UTType(typeID) else {
                    return
                }
                if utType.conforms(to: .image) || utType.conforms(to: .url) || utType.conforms(to: .fileURL) {
                    dropService.setIsAllowed(to: true)
                } else {
                    dropService.setIsAllowed(to: false)
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            dropService.setIsAllowed(to: true)
            // There is a bug where this NSItemProvider can load image but the one on performDrop(info: DropInfo) can't
            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else {
                    return
                }
                guard let image = UnifiedImage(data: data) else {
                    dropService.setIsAllowed(to: false)
                    return
                }
                dropService.temporaryImage = image
                completeDropFromTempImageHack(image)
            }
        } else {
            dropService.setIsAllowed(to: false)
            return false
        }
        dropService.isValidated = true
        return true
    }

    func performDrop(info: DropInfo) -> Bool {
        guard dropService.isGuarded == false else {
            return false
        }
//        guard dropService.isAllowed else {
//            return false
//        }
        dropService.anItemWasDropped = true
        guard let itemProvider = info.itemProviders(for: [.image, .url, .fileURL]).first else {
            dropCompleted(.failure(MediaUtilitiesError.lacksConformingTypeIdentifiers))
            return false
        }
        
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            Task {
#if os(iOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil)
                if let urlData = nsSecureCoding as? Data {
                    if let img = UnifiedImage(data: urlData) {
                        dropCompleted(.success(img))
                    } else {
                        dropCompleted(.failure(MediaUtilitiesError.badImage))
                    }
                }
#endif
#if os(macOS)
                let nsSecureCoding = try await itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
                if let urlData = nsSecureCoding as? Data {
                    let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                    if let img = NSImage(contentsOf: url) {
                        dropCompleted(.success(img))
                    } else {
                        dropCompleted(.failure(MediaUtilitiesError.badImage))
                    }
                }
#endif
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let image = dropService.temporaryImage {
                completeDropFromTempImageHack(image)
            } else {
                itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    DispatchQueue.main.async {
                        guard let data = data else {
                            dropCompleted(.failure(MediaUtilitiesError.badImage))
                            return
                        }
                        guard let img = UnifiedImage(data: data) else {
                            dropCompleted(.failure(MediaUtilitiesError.badImage))
                            return
                        }
                        dropCompleted(.success(img))
                    }
                }
            }
        }
        dropService.isValidated = false
        return true
    }
    
    func completeDropFromTempImageHack(_ image: UnifiedImage) {
        guard dropService.isGuarded == false else {
            return
        }
        guard dropService.isAllowed else {
            return
        }
        guard dropService.anItemWasDropped else {
            return
        }
        dropCompleted(.success(image))
        dropService.temporaryImage = nil
    }
}
