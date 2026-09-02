//
//  RecordingTimeView.swift
//  MediaUtilities
//
//  Created by ian on 04/12/2025.
//

import SwiftUI

/// A compact overlay showing the elapsed recording time.
///
/// `RecordingTimeView` renders a formatted timestamp (`HH:mm:ss`) on a
/// rounded badge, re-evaluated on its own periodic clock. `CameraCaptureView`
/// displays it while a video recording is in progress.
@available(iOS 14.0, macOS 11.0, *)
struct RecordingTimeView: View {
    /// The elapsed recording time in seconds, re-read on every tick.
    let timeProvider: () -> Double

    var body: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            // Self-driving clock: the timer must advance even when the preview
            // stream is paused or stalled (updating only alongside
            // `previewImage`'s ~30 fps republication froze it).
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                text
            }
        } else {
            // Falls back to parent-driven updates on older OS.
            text
        }
    }

    private var text: some View {
        Text(timeProvider().formatted)
            .foregroundColor(.white)
            .grayBackgroundRound()
    }
}

extension TimeInterval {
    /// Formats the interval as a zero-padded `HH:mm:ss` string.
    fileprivate var formatted: String {
        let time = Int(self)
        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)
        let formatString = "%0.2d:%0.2d:%0.2d"
        return String(format: formatString, hours, minutes, seconds)
    }
}
