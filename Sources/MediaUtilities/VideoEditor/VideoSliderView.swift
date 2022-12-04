//
//  VideoSliderView.swift
//  Items
//
//  Created by Ian on 23/06/2022.
//

import SwiftUI

@available(iOS 15.0, macOS 12, *)
public struct VideoSliderView: View {
    @EnvironmentObject private var playerVM: PlayerViewModel
    @EnvironmentObject private var videoUtil: VideoUtil

    @State private var startOffset: CGFloat = 0
    @State private var endOffset: CGFloat = 0
    @State private var seekerOffset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0

    @State private var isShowingSeekerTime = false
    @State private var timer: Timer?
    let seekerHeight: CGFloat = 40
    let seekerWidth: CGFloat = 5
    let adjustmentOffset: CGFloat = 13.0

    public init() { }

    public var body: some View {
        Group {
            if videoUtil.videoImageFrames.isEmpty {
                SpinnerView()
            } else {
                sliderView
            }
        }
        .transition(.move(edge: .bottom))
        .padding()
    }

    var sliderView: some View {
        ZStack {
            imageFramesView
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .mask {
                    holeShapeMaskStart
                        .fill(style: FillStyle(eoFill: true))
                }
                .frame(width: maxOffset)
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .mask {
                    holeShapeMaskEnd
                        .fill(style: FillStyle(eoFill: true))
                        .rotationEffect(.degrees(180.0))
                }
                .frame(width: maxOffset)
                .offset(x: adjustmentOffset + seekerWidth)
            seekersView
        }
        .frame(height: seekerHeight)
        .frame(maxWidth: 400)
        .padding(.bottom)
        .onChange(of: playerVM.currentTime) { _ in
            updateSeeker()
        }
    }

    var seekersView: some View {
        HStack(spacing: 0) {
            Text("|")
                .font(.system(size: seekerHeight, weight: .thin, design: .default))
                .foregroundColor(playerVM.startPlayingAt == 0 ? Color.black : Color.orange)
                .padding(.horizontal, 3)
                .padding(.bottom, 5)
                .background(Color.gray)
                .cornerRadius(5)
                .gesture(dragGestureStart)
                .offset(x: startOffset)

            Capsule()
                .frame(width: seekerWidth)
                .foregroundColor(.orange)
                .gesture(dragGestureSeeker)
                .offset(x: seekerOffset)
                .overlay(alignment: .top) {
                    overlayTime
                }

            Text("|")
                .font(.system(size: seekerHeight, weight: .thin, design: .default))
                .foregroundColor(playerVM.endPlayingAt == playerVM.duration ? Color.black : Color.orange)
                .padding(.horizontal, 3)
                .padding(.bottom, 5)
                .background(Color.gray)
                .cornerRadius(5)
                .gesture(dragGestureEnd)
                .offset(x: maxOffset)
                .offset(x: -endOffset)
            Spacer(minLength: 0.01)
        }
        .frame(width: maxOffset)
        .background(Color.gray.opacity(0.001))
        .onTapGesture { point in
            tapGestureSeeker(point)
        }
    }

    var imageFramesView: some View {
        Group {
            if videoUtil.videoURL != nil && !videoUtil.videoImageFrames.isEmpty {
                HStack(spacing: 0) {
                    ForEach(videoUtil.videoImageFrames, id: \.self) { image in
                        Image(unifiedImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: seekerHeight)
                    }
                }
                .background(WidthObtainingBackgroundView(width: $maxOffset))
                .offset(x: adjustmentOffset + seekerWidth / 2) // 13 for the seeker 2.5 to center the capsule
            }
        }
    }

    var dragGestureStart: some Gesture {
        DragGesture()
            .onChanged { value in
                startTranslationDidChange(value.translation.width)
            }
            .onEnded { _ in
                playerVM.play()
            }
    }

    var dragGestureEnd: some Gesture {
        DragGesture()
            .onChanged { value in
                endTranslationDidChange(value.translation.width)
            }
            .onEnded { _ in
                playerVM.play()
            }
    }

    var dragGestureSeeker: some Gesture {
        DragGesture()
            .onChanged { value in
                seekerTranslationDidChange(value.translation.width)
            }
            .onEnded { _ in
                playerVM.play()
            }
    }

    var holeShapeMaskStart: Path {
        let rect = CGRect(x: 0, y: 0, width: maxOffset, height: seekerHeight + 10)
        let oneSideW = rect.maxX - startOffset
        let insetRect = CGRect(x: startOffset, y: 0, width: oneSideW, height: seekerHeight + 10)
        var shape = Rectangle().path(in: rect)
        shape.addPath(Rectangle().path(in: insetRect))
        return shape
    }

    var holeShapeMaskEnd: Path {
        let rect = CGRect(x: 0, y: 0, width: maxOffset, height: seekerHeight + 10)
        let oneSideW = rect.maxX - abs(endOffset)
        let insetRect = CGRect(x: abs(endOffset), y: 0, width: oneSideW, height: seekerHeight + 10)
        var shape = Rectangle().path(in: rect)
        shape.addPath(Rectangle().path(in: insetRect))
        return shape
    }

    var overlayTime: some View {
        Text(getTime(from: playerVM.currentTime))
            .foregroundColor(.orange)
            .fixedSize(horizontal: true, vertical: false)
            .grayBackgroundRound()
            .offset(y: -40)
            .offset(x: seekerOffset)
            .opacity(isShowingSeekerTime ? 1 : 0)
    }

    var oneSecondInOffset: CGFloat {
        let percentage: CGFloat = CGFloat(1 / videoUtil.assetDuration)
        let offset = percentage * (maxOffset)
        return offset
    }

    private func startTranslationDidChange(_ startTranslation: CGFloat) {
        guard startIsValid else {
            return
        }
        playerVM.pause()
        startOffset = validStartValue(startTranslation)
        seekerOffset = startOffset
        scrubVideo()
        calculateStartTime()
    }

    private func endTranslationDidChange(_ endTranslation: CGFloat) {
        guard endIsValid else {
            return
        }
        playerVM.pause()
        endOffset = validEndValue(endTranslation)
        seekerOffset = maxOffset - endOffset
        scrubVideo()
        calculateEndTime()
    }

    private func seekerTranslationDidChange(_ seekerTranslation: CGFloat) {
        guard seekerIsValid else {
            return
        }
        playerVM.pause()
        seekerOffset = validSeekerValue(seekerTranslation)
        scrubVideo()
    }

    private var startIsValid: Bool {
        guard startOffset > -0.001 else {
            return false
        }
        guard startOffset < maxOffset - endOffset - oneSecondInOffset + 0.001 else {
            return false
        }
        return true
    }

    private var endIsValid: Bool {
        guard endOffset > -0.001 else {
            return false
        }
        guard endOffset < maxOffset - startOffset - oneSecondInOffset + 0.001 else {
            return false
        }
        return true
    }

    private var seekerIsValid: Bool {
        guard seekerOffset > -0.001 else {
            return false
        }
        guard seekerOffset < maxOffset + 0.001 - endOffset else {
            return false
        }
        return true
    }

    private func validStartValue(_ startTranslation: CGFloat) -> CGFloat {
        let value = startOffset + startTranslation

        guard value > 0 else {
            return 0
        }
        guard value < maxOffset - endOffset - oneSecondInOffset else {
            return maxOffset - endOffset - oneSecondInOffset
        }
        return value
    }

    private func validEndValue(_ endTranslation: CGFloat) -> CGFloat {
        let value = endOffset - endTranslation

        guard value < maxOffset - startOffset - oneSecondInOffset else {
            return maxOffset - startOffset - oneSecondInOffset
        }
        guard value > 0 else {
            return 0
        }
        return value
    }

    private func validSeekerValue(_ seekerTranslation: CGFloat) -> CGFloat {
        let value = seekerOffset + seekerTranslation
        let endOffset = abs(endOffset)

        guard value > startOffset - 0.001 else {
            return startOffset
        }
        guard value < maxOffset - endOffset else {
            return maxOffset - endOffset
        }
        guard value < maxOffset else {
            return maxOffset
        }
        guard value > 0 else {
            return 0
        }
        return value
    }

    private func tapGestureSeeker(_ point: CGPoint) {
        guard point.x > startOffset + adjustmentOffset + seekerWidth / 2 else {
            return
        }
        guard point.x < maxOffset - endOffset else {
            return
        }
        seekerOffset = point.x - adjustmentOffset - seekerWidth
        scrubVideo()
    }

    private func updateSeeker() {
        guard playerVM.isPlaying else {
            return
        }
        let percentage: CGFloat = CGFloat(playerVM.currentTime / playerVM.duration)
        let offset = percentage * (maxOffset - adjustmentOffset / 2)
        guard offset > startOffset else {
            seekerOffset = startOffset
            return
        }
        guard offset < maxOffset + adjustmentOffset - endOffset else {
            seekerOffset = maxOffset + adjustmentOffset - endOffset
            return
        }
        withAnimation {
            seekerOffset = offset
        }
    }

    private func scrubVideo() {
        let percentage = seekerOffset / maxOffset
        let seekVideoSeconds = Double(percentage) * playerVM.duration
        playerVM.seekTo(seekVideoSeconds)

        isShowingSeekerTime = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            withAnimation(.interactiveSpring()) {
                isShowingSeekerTime = false
            }
        }
    }

    private func calculateStartTime() {
        let percentage = seekerOffset / maxOffset
        playerVM.startPlayingAt = percentage * videoUtil.assetDuration
    }

    private func calculateEndTime() {
        let end = maxOffset - endOffset
        let percentage = end / maxOffset
        playerVM.endPlayingAt = percentage * videoUtil.assetDuration
    }

    private func getTime(from value: Double) -> String {
        if value < 60 {
            return "\(Int(value.rounded())) s"
        } else if value < 60 * 60 {
            let minutes = value / 60
            let minutesIntDouble = Double(Int(minutes))
            let seconds = (minutes - minutesIntDouble) * 60
            return "\(Int(minutes)) m \(Int(seconds.rounded())) s"
        } else {
            let hour = value / (60 * 60)
            let hourIntDouble = Double(Int(hour))
            let minutes = (hour - hourIntDouble) * 60
            let minutesIntDouble = Double(Int(minutes))
            let seconds = (minutes - minutesIntDouble) * 60
            return "\(Int(hour)) h \(Int(minutes)) m \(Int(seconds.rounded()))s"
        }
    }
}
