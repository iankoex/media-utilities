//
//  RecordingTimeView.swift
//  MediaUtilities
//
//  Created by ian on 04/12/2025.
//

import SwiftUI

@available(iOS 14.0, macOS 11.0, *)
struct RecordingTimeView: View {
    let time: Double

    var body: some View {
        Text(time.formatted)
            .foregroundColor(.white)
            .grayBackgroundRound()
    }
}

extension TimeInterval {
    fileprivate var formatted: String {
        let time = Int(self)
        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)
        let formatString = "%0.2d:%0.2d:%0.2d"
        return String(format: formatString, hours, minutes, seconds)
    }
}
