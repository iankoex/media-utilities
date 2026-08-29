//
//  PhotoCaptureDelegate.swift
//  MediaUtilities
//
//  Created by ian on 26/08/2026.
//

import AVFoundation
import Foundation

/// A per-capture delegate for `AVCapturePhotoOutput`.
///
/// `CameraService` no longer conforms directly to `AVCapturePhotoCaptureDelegate`
/// (it can't - it's `@MainActor`-isolated, and the delegate callbacks fire on
/// AVFoundation's private queue). Instead, a new `PhotoCaptureDelegate` is
/// created for each photo capture, holds its own continuation, and resumes
/// the continuation directly when the delegate fires.
///
/// The delegate retains itself for the lifetime of the capture via `retained`.
/// `AVCapturePhotoOutput` only holds a weak reference to its delegate, and
/// the closure that created this delegate returns to its caller immediately
/// after registration, so without self-retention the delegate would be
/// deallocated and the continuation would leak. `retained` is nilled inside
/// the continuation-resume path.
@available(iOS 13.0, macOS 10.15, *)
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let continuation: CheckedContinuation<URL?, Never>
    private let photoStreamContinuation: AsyncStream<AVCapturePhoto>.Continuation?

    /// Self-retention. Set immediately after init so the delegate lives until
    /// it resumes the continuation. Nilled inside the continuation-resume path.
    private var retained: PhotoCaptureDelegate?

    init(
        continuation: CheckedContinuation<URL?, Never>,
        photoStreamContinuation: AsyncStream<AVCapturePhoto>.Continuation?
    ) {
        self.continuation = continuation
        self.photoStreamContinuation = photoStreamContinuation
        super.init()
        // Capture self to keep the delegate alive across the async AVFoundation
        // callback. Released when the continuation is resumed below.
        self.retained = self
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Always release the self-retention once the continuation has been resumed.
        defer { retained = nil }

        if error != nil {
            continuation.resume(returning: nil)
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            continuation.resume(returning: nil)
            return
        }

        // HEVC captures are HEIC data - sniff the payload to pick the
        // extension instead of assuming JPEG. JPEG begins with the FF D8
        // marker; the HEVC photo path produces a HEIC container.
        let pathExtension = imageData.starts(with: [0xFF, 0xD8]) ? "jpg" : "heic"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera_photo_\(UUID().uuidString).\(pathExtension)")

        do {
            try imageData.write(to: tempURL)
            photoStreamContinuation?.yield(photo)
            continuation.resume(returning: tempURL)
        } catch {
            continuation.resume(returning: nil)
        }
    }
}
