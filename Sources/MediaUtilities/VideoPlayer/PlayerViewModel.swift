//
//  File 2.swift
//  
//
//  Created by Ian on 04/12/2022.
//

import Combine
import AVFoundation

@available(iOS 13.0, macOS 10.15, *)
final public class PlayerViewModel: ObservableObject {
    public let player = AVPlayer()
    @Published public var allowsPictureInPicturePlayback: Bool = true
    @Published public var isPlaying = false
    @Published public var isMuted = false
    @Published public var loopPlayback = true
    @Published public var isShowingControls = true
    @Published public var isEditingCurrentTime = false
    @Published public var currentTime: Double = .zero
    @Published public var duration: Double = .zero
    @Published public var startPlayingAt: Double = .zero
    @Published public var endPlayingAt: Double = .zero

    private var subscriptions: Set<AnyCancellable> = []
    private var timeObserver: Any?

    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    public init() {
        $isEditingCurrentTime
            .dropFirst()
            .filter({ $0 == false })
            .sink(receiveValue: { [weak self] _ in
                guard let self = self else { return }
                self.player.seek(to: CMTime(seconds: self.currentTime, preferredTimescale: 1), toleranceBefore: .zero, toleranceAfter: .zero)
                if self.player.rate != 0 {
                    self.player.play()
                }
            })
            .store(in: &subscriptions)

        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                switch status {
                case .playing:
                    self?.isPlaying = true
                case .paused:
                    self?.isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &subscriptions)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.updateCurrentTime(time)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    public func setCurrentItem(_ url: URL) {
        currentTime = .zero
        duration = .zero
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        item.publisher(for: \.status)
            .filter({ $0 == .readyToPlay })
            .sink(receiveValue: { [weak self] _ in
                self?.duration = item.asset.duration.seconds
            })
            .store(in: &subscriptions)
    }

    public func seekForward() {
        var time = currentTime + 10
        if time >= duration {
            time = duration
        }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
        player.play()
    }

    public func seekBackward() {
        var time = currentTime - 10
        if time <= 0 {
            time = 0
        }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 1000))
        player.play()
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seekTo(_ seconds: Double) {
        let cmTime = CMTime(seconds: seconds, preferredTimescale: 1000)
        player.seek(to: cmTime)
    }

    private func updateCurrentTime(_ time: CMTime) {
        self.currentTime = time.seconds
        if endPlayingAt != 0 && currentTime > endPlayingAt {
            endPlayingAtReached()
        }
    }

    private func endPlayingAtReached() {
        if loopPlayback {
            seekTo(startPlayingAt)
            player.play()
        } else {
            player.pause()
        }
    }

    @objc private func playerItemDidReachEnd(notification: NSNotification) {
        if loopPlayback {
            seekTo(startPlayingAt)
            player.play()
        }
    }
}
