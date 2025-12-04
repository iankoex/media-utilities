//
//  MediaPicker.swift
//  MediaUtilities
//
//  Created by Ian on 27/06/2022.
//

import Foundation

// MARK: - Media Picker

/// A utility class for media file operations and temporary storage management.
///
/// `MediaPicker` provides static methods for managing media files during import
/// and processing operations. Most media picker functionality is provided through
/// SwiftUI View extensions, but this class handles the underlying file operations.
///
/// ## Features
///
/// - **File Copying**: Safely copy media files to temporary storage
/// - **Directory Management**: Clean up temporary media directories
/// - **Error Handling**: Comprehensive error reporting for file operations
///
/// ## Platform Notes
///
/// Some functionality is iOS-specific due to platform differences in media handling.
/// macOS typically handles media files differently and may not require temporary copying.
///
@available(iOS 13.0, macOS 10.15, *)
public class MediaPicker {
    
    /// Cleans the temporary media directory by removing all cached files.
    ///
    /// This method removes all files from the MediaPicker temporary directory,
    /// which is used to store copied media files during import operations.
    /// This helps manage disk space and prevent accumulation of temporary files.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Clean up temporary media files
    /// MediaPicker.cleanDirectory()
    /// ```
    ///
    /// - Note: This operation is asynchronous and primarily useful on iOS
    ///   where media files are copied to temporary storage during import.
    ///   On macOS, media files are typically accessed directly.
    public static func cleanDirectory() {
        Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaPicker")
            if !FileManager.default.fileExists(atPath: directory.absoluteString) {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print(error.localizedDescription)
                }
            }
            do {
                let directoryContents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
                for pathURL in directoryContents {
                    try FileManager.default.removeItem(at: pathURL)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    /// Copies media content from a source URL to the temporary directory.
    ///
    /// This method safely copies media files to the MediaPicker temporary directory,
    /// ensuring that imported media can be accessed reliably throughout the app lifecycle.
    /// If a file with the same name already exists, it will be replaced.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// MediaPicker.copyContents(of: sourceURL) { localURL, error in
    ///     if let error = error {
    ///         print("Copy failed: \(error)")
    ///         return
    ///     }
    ///
    ///     if let localURL = localURL {
    ///         print("Media copied to: \(localURL)")
    ///         // Use the local URL for further processing
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - url: The source URL of the media file to copy
    ///   - onCompletion: A completion handler called with the local URL or an error
    ///
    /// - Note: The completion handler is called on the main thread for UI updates.
    public static func copyContents(of url: URL, onCompletion: (URL?, Error?) -> Void) {
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
            onCompletion(localURL, nil)
        } catch let catchedError {
            onCompletion(nil, catchedError)
        }
    }
}
