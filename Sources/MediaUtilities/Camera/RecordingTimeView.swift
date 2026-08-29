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
/// rounded badge. `CameraCaptureView` displays it while a video recording
/// is in progress.
@available(iOS 14.0, macOS 11.0, *)
struct RecordingTimeView: View {
    /// The elapsed recording time in seconds.
    let time: Double

    var body: some View {
        Text(time.formatted)
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
