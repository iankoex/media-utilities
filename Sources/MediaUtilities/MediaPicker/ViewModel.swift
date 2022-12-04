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
class ViewModel: ObservableObject {
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
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaPicker")
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }
            let localURL: URL = directory.appendingPathComponent(url.lastPathComponent)
            
            if FileManager.default.fileExists(atPath: localURL.path) {
                try? FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: url, to: localURL)
            DispatchQueue.main.async {
                self.pathURLs.append(localURL)
            }
        } catch let catchedError {
            DispatchQueue.main.async {
                self.errors.append(catchedError)
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
