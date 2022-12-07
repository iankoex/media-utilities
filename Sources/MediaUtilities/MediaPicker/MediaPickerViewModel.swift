//
//  File.swift
//  
//
//  Created by Ian on 29/06/2022.
//

#if os(iOS)
import Foundation
import PhotosUI
import SwiftUI

@available(iOS 14.0, macOS 11, *)
class MediaPickerViewModel: ObservableObject {
    var onCompletion: (Result<[URL], Error>) -> Void
    var configuration: PHPickerConfiguration = PHPickerConfiguration(photoLibrary: .shared())
    var allowedContentTypes: [UTType] = []
    @Published var progress: Progress = Progress()
    @Published var pathURLs: [URL] = []
    @Published var errors: [Error] = []
    @Published var isLoading: Bool = false
    
    
    init(onCompletion: @escaping (Result<[URL], Error>) -> Void) {
        self.onCompletion = onCompletion
    }
    
    func handleResults(for results: [PHPickerResult]) {
        withAnimation {
            isLoading = true
        }
        progress.totalUnitCount = Int64(results.count)
        for result in results {
            let contentTypes = allowedContentTypes
            for contentType in contentTypes {
                let itemProvider = result.itemProvider
                if itemProvider.hasItemConformingToTypeIdentifier(contentType.identifier) {
                    loadFile(for: itemProvider, ofType: contentType)
                }
            }
        }
    }
    
    private func loadFile(for itemProvider: NSItemProvider, ofType contentType: UTType) {
        let progress: Progress? = itemProvider.loadFileRepresentation(forTypeIdentifier: contentType.identifier) { url, error in
            guard let url = url, error == nil else {
                DispatchQueue.main.async {
                    self.errors.append(error!)
                }
                return
            }
            self.copyFile(from: url)
        }
        if let progress = progress {
            self.progress.addChild(progress, withPendingUnitCount: 1)
        }
    }
    
    private func copyFile(from url: URL) {
        MediaPicker.copyContents(of: url) { localURL, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async {
                    self.errors.append(error!)
                }
                return
            }
            DispatchQueue.main.async {
                self.pathURLs.append(localURL)
            }
        }
    }
    
    func finaliseResults() {
        if pathURLs.isEmpty {
            onCompletion(.failure(errors[0]))
        } else {
            onCompletion(.success(pathURLs))
        }
        withAnimation {
            isLoading = false
        }
    }
}
#endif
