//
//  VideoDataOutputDelegate.swift
//  MediaUtilities
//
//  Created by ian on 26/08/2026.
//

import AVFoundation
import CoreImage
import Foundation

/// A long-lived delegate for `AVCaptureVideoDataOutput` that yields frames
/// into the engine's preview stream.
///
/// `CameraService` no longer conforms directly to
/// `AVCaptureVideoDataOutputSampleBufferDelegate`. A single
/// `VideoDataOutputDelegate` is created when the session is configured and
/// held for the lifetime of the session. Frames are yielded to the preview
/// stream continuation directly (continuations are thread-safe). The
/// preview-pause flag is read from the engine via a `nonisolated(unsafe)`
/// word-sized property, avoiding any actor hop per frame.
@available(iOS 13.0, macOS 10.15, *)
final class VideoDataOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let previewStreamContinuation: AsyncStream<CIImage>.Continuation?
    private weak var engine: CameraEngine?

    init(
        engine: CameraEngine,
        previewStreamContinuation: AsyncStream<CIImage>.Continuation?
    ) {
        self.engine = engine
        self.previewStreamContinuation = previewStreamContinuation
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // No per-frame rotation/mirroring here. The video data output connection
        // is pinned to 0° at session setup (before startRunning), and rotation +
        // mirroring are applied in the CIImage→Image transform based on the active
        // camera position. This avoids the double-mirror and the unsupported
        // per-frame videoRotationAngle-after-startRunning usage.

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Read the pause flag without an actor hop.
        guard let engine, !engine.isPreviewPausedNow() else { return }

        previewStreamContinuation?.yield(ciImage)
    }
}
