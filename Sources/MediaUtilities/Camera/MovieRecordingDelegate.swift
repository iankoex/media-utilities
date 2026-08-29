//
//  MovieRecordingDelegate.swift
//  MediaUtilities
//
//  Created by ian on 26/08/2026.
//

import AVFoundation
import Foundation

/// A per-recording delegate for `AVCaptureMovieFileOutput`.
///
/// `CameraService` no longer conforms directly to `AVCaptureFileOutputRecordingDelegate`.
/// A new `MovieRecordingDelegate` is created for each recording; its only job
/// is to forward the finish callback into the `CameraEngine` actor, which owns
/// all recording state (the pending stop continuation, the stream yield, and
/// the delegate retention). The engine is referenced weakly - the engine holds
/// the strong reference for the lifetime of the recording.
@available(iOS 13.0, macOS 10.15, *)
final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {

    private weak var engine: CameraEngine?

    init(engine: CameraEngine?) {
        self.engine = engine
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Hop into the engine actor: all recording state mutations - clearing
        // the retained delegate, resuming the pending stop continuation, and
        // yielding the finished URL - are serialized there against the
        // engine-side stop request.
        let engine = self.engine
        Task { await engine?.movieRecordingDidFinish(url: outputFileURL, error: error) }
    }
}
