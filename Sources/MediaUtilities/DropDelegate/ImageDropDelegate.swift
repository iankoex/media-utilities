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
        print("Here 1")
        guard dropService.isGuarded == false else {
            return false
        }
        print("Here 2")
        guard let itemProvider = info.itemProviders(for: [.image, .url, .fileURL]).first else {
            return false
        }
        print("Here 3")
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                print("Here 4")
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
                    print("Here 7 11")
                } else {
                    dropService.setIsAllowed(to: false)
                    print("Here 7 22")
                }
            }
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            print("here 8")
            itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data = data else {
                    return
                }
                let img = UnifiedImage(data: data)
                guard img != nil else {
                    dropService.setIsAllowed(to: false)
                    return
                }
                print("here 10")
                dropService.setIsAllowed(to: true)
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
        guard dropService.isAllowed else {
            return false
        }
        if let item = info.itemProviders(for: [.image, .url, .fileURL]).first {
            if item.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                Task {
                    #if os(iOS)
                    let nsSecureCoding = try await item.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil)
                    if let urlData = nsSecureCoding as? Data {
                        if let img = UnifiedImage(data: urlData) {
                            dropCompleted(.success(img))
                        } else {
                            dropCompleted(.failure(DropDelegateError.badImage))
                        }
                        withAnimation {
//                            isActive = false
                        }
                    }
                    #endif
                    #if os(macOS)
                    let nsSecureCoding = try await item.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil)
                    if let urlData = nsSecureCoding as? Data {
                        let url = NSURL(absoluteURLWithDataRepresentation: urlData, relativeTo: nil) as URL
                        if let img = NSImage(contentsOf: url) {
                            dropCompleted(.success(img))
                        } else {
                            dropCompleted(.failure(DropDelegateError.badImage))
                        }
                    }
                    #endif
                }
            } else if item.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                item.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data = data else {
                        dropCompleted(.failure(DropDelegateError.badImage))
                        return
                    }
                    guard let img = UnifiedImage(data: data) else {
                        dropCompleted(.failure(DropDelegateError.badImage))
                        return
                    }
                    dropCompleted(.success(img))
                }
            }
        } else {
            dropCompleted(.failure(DropDelegateError.lacksConformingTypeIdentifiers))
            return false
        }
        dropService.isValidated = false
        return true
    }
}
