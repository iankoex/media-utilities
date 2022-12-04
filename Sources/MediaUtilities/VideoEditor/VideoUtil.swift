//
//  VideoKit.swift
//  Items
//
//  Created by Ian on 23/06/2022.
//

import Foundation
import AVFoundation
import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
class VideoUtil: ObservableObject {
    @Published var progress: Double = .zero
    @Published var videoImageFrames: [UnifiedImage] = []
    private var asset: AVAsset?
    private var timer: Timer?
    private(set) var exporter: AVAssetExportSession?
    private var images: [UnifiedImage] = []

    var videoURL: URL? {
        didSet {
            asset = AVURLAsset(url: videoURL!, options: nil)
            generateImageFrames()
        }
    }

    var assetDuration: Double {
        asset?.duration.seconds ?? 0
    }

    func trim(from preferredStartTime: Double, to preferredEndTime: Double, with preset: Quality, callback: @escaping (_ result: Result) -> Void) {
//        check if the asset is an online video or a local one if one dowload it first else the exporter will fail
        guard let asset = asset else {
            callback(.error("asset not set, asset is nil"))
            return
        }

        let outputVideoURL = outputURL()
        exporter = AVAssetExportSession(asset: asset, presetName: preset.value)

        guard let exporter = exporter else {
            callback(.error("exporter INIT FAILED"))
            return
        }

        var startTime = CMTime(seconds: preferredStartTime, preferredTimescale: 1000)
        var endTime = CMTime(seconds: preferredEndTime, preferredTimescale: 1000)
        if preferredStartTime < 0 {
            startTime = .zero
        }
        if preferredEndTime > assetDuration {
            endTime = asset.duration
        }
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        exporter.outputURL = outputVideoURL
        exporter.outputFileType = .mp4
        exporter.timeRange = timeRange
        exporter.exportAsynchronously {
            if exporter.status == .completed {
                DispatchQueue.main.async {
                    callback(.success(outputVideoURL))
                }
            }
        }
        observeExporter(callback: callback)
    }

    func observeExporter(callback: @escaping (_ result: Result) -> Void) {
        guard let exporter = exporter else {
            callback(.error("exporter INIT FAILED"))
            return
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            withAnimation {
                self.progress = Double(exporter.progress)
            }
            if exporter.status == .completed || exporter.status == .failed || exporter.status == .cancelled {
                self.timer?.invalidate()
                if exporter.status == .cancelled {
                    callback(.error("exporter was cancelled"))
                }
                if exporter.status == .failed {
                    callback(.error("exporter Failed"))
                }
            }
        }
    }

    func outputURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VideoEditor")
        if !FileManager.default.fileExists(atPath: directory.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        let pathC = "trimmedVideo\(videoURL?.lastPathComponent ?? "nil").mp4"
        let url = directory.appendingPathComponent(pathC)
        // If the file exists at the URL, the exporter will fail.
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    func generateImageFrames() {
        Task(priority: .background) {
            guard let asset = asset else {
                return
            }
            let imgGenerator = AVAssetImageGenerator(asset: asset)
            // reduces RAM usage for 4K videos
            imgGenerator.maximumSize = CGSize(width: 512, height: 512)

            let assetDuration = asset.duration.seconds

            for index in 1 ... 11 {
                do {
                    let timeInSeconds = assetDuration / 10 * Double(index)
                    let time: CMTime = .init(seconds: timeInSeconds, preferredTimescale: 1000)
                    let img = try imgGenerator.copyCGImage(at: time, actualTime: nil)
                    let image = UnifiedImage(cgImage: img)
                    images.append(image)
                } catch {
                    print("Image generation failed with error \(error.localizedDescription)")
                }
            }

            DispatchQueue.main.async {
                self.videoImageFrames = self.images
            }
        }
    }

    static func cleanDirectory() {
        Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VideoEditor")
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
}

@available(iOS 13.0, macOS 10.15, *)
extension VideoUtil {
    enum Result {
        case success(_ videoURL: URL)
        case error(_ errorString: String)
    }

    enum Quality {
        case preset640x480
        case preset960x540
        case preset1280x720
        case preset1920x1080
        case preset3840x2160
        case presetHEVC1920x1080
        case presetLowQuality
        case presetMediumQuality
        case presetHighestQuality
        case presetPassthrough

        var value: String {
            switch self {
            case .preset640x480:
                return AVAssetExportPreset640x480
            case .preset960x540:
                return AVAssetExportPreset960x540
            case .preset1280x720:
                return AVAssetExportPreset1280x720
            case .preset1920x1080:
                return AVAssetExportPreset1920x1080
            case .preset3840x2160:
                return AVAssetExportPreset3840x2160
            case .presetHEVC1920x1080:
                return AVAssetExportPresetHEVC1920x1080
            case .presetLowQuality:
                return AVAssetExportPresetLowQuality
            case .presetMediumQuality:
                return AVAssetExportPresetMediumQuality
            case .presetHighestQuality:
                return AVAssetExportPresetHighestQuality
            case .presetPassthrough:
                return AVAssetExportPresetPassthrough
            }
        }
    }
}
