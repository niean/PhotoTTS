import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import os.log

// MARK: - 翻页动画样式

/// 翻页动画方向（相对横屏控制层坐标系）
private enum AnimationStyle {
    /// 从右到左（默认）
    case rightToLeft
    /// 从上到下
    case topToBottom
}

// MARK: - 播放器

/// 竖屏播放器：图片保持拍摄原始方向，全屏展示。
/// 操作控件（播控、进度条、控制栏）悬浮在图片之上。
/// 图片切换由音频进度自动驱动（播放中），或由用户拖动进度条手动控制（暂停时）。
struct PlayView: View {
    var recordId: String? = nil
    var preloadedRecord: SessionRecord? = nil
    let onDismiss: () -> Void

    @State private var record: SessionRecord?
    /// 仅当从制作页传入的 preloadedRecord 时为 true
    @State private var recordIsFromPreload = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var currentImageIndex = 0
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var playbackTimer: Timer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate: AudioPlayerDelegate?
    @State private var textSegmentRanges: [(start: Int, end: Int)] = []
    /// 制作页传入的预加载图片
    @State private var preloadedImages: [UIImage]? = nil
    @State private var isOverlayVisible = false
    @State private var overlayAutoHideTimer: Timer?
    /// "播完本集"定时关闭，默认开启（播完自动退出，与原行为一致）
    @State private var autoStopEnabled = true
    /// 护眼模式：开启时使用护眼绿背景，关闭时使用黑色背景
    @State private var eyeProtectionEnabled = true
    /// 撑满全屏：开启时图片 .fit 拉伸填满可用空间（现有行为），关闭时以原尺寸展示（不放大，仅缩小以适屏）
    @State private var fillScreenEnabled = true
    /// 翻页动画样式：从右到左（默认）或从上到下（相对横屏控制层）
    @State private var animationStyle: AnimationStyle = .rightToLeft
    /// 翻页方向：true=正向(index增大)，false=反向(index减小)，用于动态控制 transition 方向
    @State private var isForwardTransition: Bool = true

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    private let overlayAutoHideInterval: TimeInterval = Constants.Playback.overlayAutoHideInterval
    private var playButtonSize: CGFloat { scaled(25) }
    private var controlButtonSize: CGFloat { scaled(40) }

    /// 进度条分割点比例（0.0~1.0），每页音频段的起始位置
    private var segmentRatios: [Double] {
        guard let record = record, !textSegmentRanges.isEmpty else { return [] }
        let total = record.ocrText.count
        guard total > 0 else { return [] }
        return textSegmentRanges.map { Double($0.start) / Double(total) }
    }

    private var currentAudioTime: TimeInterval { audioPlayer?.currentTime ?? 0 }
    private var totalAudioDuration: TimeInterval { audioPlayer?.duration ?? 0 }

    var body: some View {
        Group {
            if isLoading {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    ProgressView("加载中...")
                }
            } else if let record = record, record.totalImageCount > 0 {
                playerView(record: record)
            } else if loadError != nil {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text(loadError ?? "加载失败")
                            .foregroundColor(.secondary)
                        Button("关闭", action: { stopAndDismiss() })
                    }
                }
            } else {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    Button("关闭", action: { stopAndDismiss() })
                }
            }
        }
        .onAppear {
            if let pre = preloadedRecord {
                record = pre
                recordIsFromPreload = true
                preloadedImages = pre.getImages()
                textSegmentRanges = computeTextSegmentRanges(pre.ocrTextSegments)
                isLoading = false
                if pre.getAudioData() != nil { startPlayback() }
            } else {
                recordIsFromPreload = false
                loadRecord()
            }
        }
        .onDisappear {
            stopAudio()
            overlayAutoHideTimer?.invalidate()
            overlayAutoHideTimer = nil
            onDismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.remotePlaybackCommand)) { notification in
            guard let action = notification.userInfo?["action"] as? String else { return }
            switch action {
            case "play": resumeIfPaused()
            case "pause": pauseIfPlaying()
            case "toggle": togglePlayback()
            default: break
            }
        }
        // 禁用后台播放：锁屏/切APP时主动暂停
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            pauseIfPlaying()
        }
    }

    // MARK: - 播放器主视图

    @ViewBuilder
    private func playerView(record: SessionRecord) -> some View {
        let useOnDemand = !recordIsFromPreload
        GeometryReader { geometry in
            ZStack {
                // 底层：护眼底色 + 手势区域
                (eyeProtectionEnabled ? Constants.Playback.eyeProtectionBackgroundColor : Color.black)
                    .ignoresSafeArea(.all)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard audioPlayer != nil else { return }
                        togglePlayback()
                        if isOverlayVisible { startOverlayAutoHideTimer() }
                    }
                    .onTapGesture {
                        isOverlayVisible.toggle()
                        if isOverlayVisible { startOverlayAutoHideTimer() }
                    }
                    // 手势识别：暂停状态下支持滑动切换图片，方向受动画样式管控
                    .gesture(
                        DragGesture(minimumDistance: Constants.Gesture.swipeMinDistance)
                            .onEnded { value in
                                guard !isPlaying, audioPlayer != nil else { return }
                                let newIndex: Int
                                switch animationStyle {
                                case .rightToLeft:
                                    // 竖屏 height- = 用户横屏左滑 -> 下一张；height+ = 用户横屏右滑 -> 上一张
                                    let t = value.translation.height
                                    if t < -Constants.Gesture.swipeMinDistance {
                                        newIndex = min(currentImageIndex + 1, record.totalImageCount - 1)
                                    } else if t > Constants.Gesture.swipeMinDistance {
                                        newIndex = max(0, currentImageIndex - 1)
                                    } else {
                                        return
                                    }
                                case .topToBottom:
                                    // 竖屏 width+ = 用户横屏上滑 -> 上一张；width- = 用户横屏下滑 -> 下一张
                                    let t = value.translation.width
                                    if t > Constants.Gesture.swipeMinDistance {
                                        newIndex = max(0, currentImageIndex - 1)
                                    } else if t < -Constants.Gesture.swipeMinDistance {
                                        newIndex = min(currentImageIndex + 1, record.totalImageCount - 1)
                                    } else {
                                        return
                                    }
                                }
                                guard newIndex != currentImageIndex else { return }
                                isForwardTransition = newIndex > currentImageIndex
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentImageIndex = newIndex
                                }
                                // 同步音频位置到新页对应文本段起始
                                if newIndex < segmentRatios.count {
                                    seekToRatio(segmentRatios[newIndex])
                                }
                            }
                    )

                // 图片层（不响应手势，传递给底层）
                PlayerImageView(
                    sessionId: useOnDemand ? record.id : nil,
                    preloadedImages: useOnDemand ? nil : preloadedImages,
                    index: currentImageIndex,
                    size: geometry.size,
                    fillScreen: fillScreenEnabled
                )
                .id(currentImageIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: {
                        switch (animationStyle, isForwardTransition) {
                        case (.rightToLeft, true): return .bottom
                        case (.rightToLeft, false): return .top
                        case (.topToBottom, true): return .trailing
                        case (.topToBottom, false): return .leading
                        }
                    }()),
                    removal: .move(edge: {
                        switch (animationStyle, isForwardTransition) {
                        case (.rightToLeft, true): return .top
                        case (.rightToLeft, false): return .bottom
                        case (.topToBottom, true): return .leading
                        case (.topToBottom, false): return .trailing
                        }
                    }())
                ))
                .allowsHitTesting(false)

                // 控制层：横屏布局，旋转 +90° 覆盖在竖屏图片之上（适配手机左侧为底的横屏观看）
                if isOverlayVisible {
                    PlayerControlLayer(
                        isPlaying: isPlaying,
                        autoStopEnabled: autoStopEnabled,
                        showProgressBar: audioPlayer != nil,
                        isPlayEnabled: record.getAudioData() != nil,
                        playbackProgress: playbackProgress,
                        currentAudioTime: currentAudioTime,
                        totalAudioDuration: totalAudioDuration,
                        segmentRatios: segmentRatios,
                        isDraggable: !isPlaying,
                        eyeProtectionEnabled: eyeProtectionEnabled,
                        fillScreenEnabled: fillScreenEnabled,
                        animationStyle: animationStyle,
                        onTogglePlayback: { togglePlayback() },
                        onToggleAutoStop: { autoStopEnabled.toggle() },
                        onToggleEyeProtection: { eyeProtectionEnabled.toggle() },
                        onToggleFillScreen: { fillScreenEnabled.toggle() },
                        onToggleAnimationStyle: {
                            animationStyle = animationStyle == .rightToLeft ? .topToBottom : .rightToLeft
                        },
                        onDismiss: { stopAndDismiss() },
                        onHideOverlay: { isOverlayVisible = false },
                        onSeek: { seekToRatio($0) },
                        onInteraction: { startOverlayAutoHideTimer() }
                    )
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
        .onAppear {
            if isOverlayVisible { startOverlayAutoHideTimer() }
            if !recordIsFromPreload {
                preloadAdjacentImages(sessionId: record.id, current: currentImageIndex, total: record.totalImageCount)
            }
        }
        .onChange(of: isOverlayVisible) { _, visible in
            if !visible { overlayAutoHideTimer?.invalidate(); overlayAutoHideTimer = nil }
            else { startOverlayAutoHideTimer() }
        }
        .onChange(of: currentImageIndex) { _, newIndex in
            if !recordIsFromPreload {
                preloadAdjacentImages(sessionId: record.id, current: newIndex, total: record.totalImageCount)
            }
        }
    }

    // MARK: - 数据加载

    private func loadRecord() {
        guard let id = recordId else { isLoading = false; return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let loaded = SessionRecordManager.shared.loadSession(id: id) else {
                DispatchQueue.main.async {
                    loadError = "无法加载会话"
                    isLoading = false
                }
                return
            }
            DispatchQueue.main.async {
                record = loaded
                textSegmentRanges = computeTextSegmentRanges(loaded.ocrTextSegments)
                isLoading = false
                if loaded.getAudioData() != nil {
                    startPlayback()
                }
            }
        }
    }

    private func computeTextSegmentRanges(_ segments: [String]) -> [(start: Int, end: Int)] {
        var ranges: [(start: Int, end: Int)] = []
        var pos = 0
        for segment in segments {
            let start = pos
            pos += segment.count
            ranges.append((start, pos))
        }
        return ranges
    }

    // MARK: - 播放控制

    private func startPlayback() {
        guard let record = record, let audioData = record.getAudioData() else { return }
        configureAudioSession()
        do {
            let player = try AVAudioPlayer(data: audioData)
            let delegate = AudioPlayerDelegate {
                DispatchQueue.main.async { onPlaybackFinished() }
            }
            player.delegate = delegate
            guard player.prepareToPlay(), player.play() else { return }
            audioPlayer = player
            audioPlayerDelegate = delegate
            isPlaying = true
            playbackProgress = 0
            startPlaybackTimer()
            UIApplication.shared.isIdleTimerDisabled = true
            setupRemoteTransportControls()
        } catch {
            os.Logger.audioPlayer.error("PlayView 创建播放器失败: \(error.localizedDescription)")
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = audioPlayer, player.duration > 0 else { return }
            let progress = player.currentTime / player.duration
            playbackProgress = progress
            updateCurrentImageIndex(progress)
        }
    }

    private func updateCurrentImageIndex(_ progress: Double) {
        guard let record = record, !textSegmentRanges.isEmpty else { return }
        let totalChars = record.ocrText.count
        guard totalChars > 0 else { return }
        let pos = Int(Double(totalChars) * progress)
        for (index, range) in textSegmentRanges.enumerated() {
            if pos >= range.start && pos < range.end {
                if index != currentImageIndex && index < record.totalImageCount {
                    isForwardTransition = index > currentImageIndex
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentImageIndex = index
                    }
                }
                return
            }
        }
        if progress >= 1.0, !textSegmentRanges.isEmpty {
            currentImageIndex = min(textSegmentRanges.count - 1, record.totalImageCount - 1)
        }
    }

    private func togglePlayback() {
        guard audioPlayer != nil else { return }
        if audioPlayer?.isPlaying == true {
            pauseIfPlaying()
        } else {
            resumeIfPaused()
        }
    }

    private func resumeIfPaused() {
        guard let player = audioPlayer, !player.isPlaying else { return }
        player.play()
        isPlaying = true
        startPlaybackTimer()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func pauseIfPlaying() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func onPlaybackFinished() {
        isPlaying = false
        playbackProgress = 1.0
        playbackTimer?.invalidate()
        playbackTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        clearRemoteTransportControls()
        if let r = record {
            PlayHistoryManager.shared.recordPlay(sessionId: r.id, name: r.name, playedAt: Date())
        }
        if autoStopEnabled {
            // 播完本集：自动退出（默认行为）
            stopAndDismiss()
        } else {
            // 不自动退出：停留在最后一帧
            audioPlayer = nil
            audioPlayerDelegate = nil
        }
    }

    private func stopAudio() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil
        UIApplication.shared.isIdleTimerDisabled = false
        clearRemoteTransportControls()
    }

    private func stopAndDismiss() {
        stopAudio()
        onDismiss()
    }

    // MARK: - 进度条跳转

    /// 跳转到指定进度比例，更新音频位置和图片
    private func seekToRatio(_ ratio: Double) {
        guard let player = audioPlayer, player.duration > 0 else { return }
        let clampedRatio = max(0, min(1, ratio))
        player.currentTime = clampedRatio * player.duration
        playbackProgress = clampedRatio
        updateCurrentImageIndex(clampedRatio)
    }

    // MARK: - 音频会话

    private func configureAudioSession() {
        // 使用 .playback：忽略静音开关，扬声器始终可出声；后台暂停由 willResignActiveNotification 控制
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Now Playing / 远程控制

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.NotificationNames.remotePlaybackCommand,
                    object: nil,
                    userInfo: ["action": "play"]
                )
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.NotificationNames.remotePlaybackCommand,
                    object: nil,
                    userInfo: ["action": "pause"]
                )
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Constants.NotificationNames.remotePlaybackCommand,
                    object: nil,
                    userInfo: ["action": "toggle"]
                )
            }
            return .success
        }
    }

    private func clearRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
    }

    // MARK: - 控制层自动隐藏

    private func startOverlayAutoHideTimer() {
        overlayAutoHideTimer?.invalidate()
        overlayAutoHideTimer = Timer.scheduledTimer(withTimeInterval: overlayAutoHideInterval, repeats: false) { _ in
            DispatchQueue.main.async {
                isOverlayVisible = false
            }
        }
    }

    // MARK: - 图片预加载

    private func preloadAdjacentImages(sessionId: String, current: Int, total: Int) {
        let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension
        if current + 1 < total {
            SessionRecordManager.shared.preloadImage(sessionId: sessionId, index: current + 1, maxDimension: maxDim)
        }
        if current - 1 >= 0 {
            SessionRecordManager.shared.preloadImage(sessionId: sessionId, index: current - 1, maxDimension: maxDim)
        }
    }
}

// MARK: - 播放器控制层（横屏布局，旋转 +90° 覆盖在竖屏图片之上）

/// 横屏播放器控制层：内部按横屏布局（宽>高），由 PlayView 旋转 +90° 后叠加在竖屏图片之上。
/// 旋转映射（+90° CW，适配手机左侧为底的横屏观看）：横屏 bottom-left -> 竖屏 top-left -> 用户横屏 bottom-left，
/// 横屏 top-right -> 竖屏 bottom-right -> 用户横屏 top-right。HStack 内左→右顺序在用户横屏视角下保持不变。
private struct PlayerControlLayer: View {
    let isPlaying: Bool
    let autoStopEnabled: Bool
    let showProgressBar: Bool
    let isPlayEnabled: Bool
    let playbackProgress: Double
    let currentAudioTime: TimeInterval
    let totalAudioDuration: TimeInterval
    let segmentRatios: [Double]
    let isDraggable: Bool
    let eyeProtectionEnabled: Bool
    let fillScreenEnabled: Bool
    let animationStyle: AnimationStyle
    let onTogglePlayback: () -> Void
    let onToggleAutoStop: () -> Void
    let onToggleEyeProtection: () -> Void
    let onToggleFillScreen: () -> Void
    let onToggleAnimationStyle: () -> Void
    let onDismiss: () -> Void
    let onHideOverlay: () -> Void
    let onSeek: (Double) -> Void
    let onInteraction: () -> Void

    @State private var isSettingsPanelVisible = false
    private var playButtonSize: CGFloat { scaled(25) }
    private var controlButtonSize: CGFloat { scaled(40) }

    /// 设备自适应缩放快捷方法（iPhone 返回原值，iPad 按比例放大）
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ZStack {
            // 横屏 bottom-left（旋转后 -> 用户横屏 bottom-left）：时间 + 进度条 + 操作按钮
            VStack(alignment: .leading, spacing: 10) {
                // 时间显示
                if showProgressBar {
                    HStack(spacing: 4) {
                        Text(formatTime(currentAudioTime))
                            .foregroundColor(Constants.Playback.progressBarFillColor)
                        Text("/")
                            .foregroundColor(.white.opacity(0.6))
                        Text(formatTime(totalAudioDuration))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                }

                // 进度条
                if showProgressBar {
                    PlayerProgressBar(
                        progress: playbackProgress,
                        segmentRatios: segmentRatios,
                        isDraggable: isDraggable,
                        onSeek: { ratio in
                            onSeek(ratio)
                            onInteraction()
                        }
                    )
                }

                // 操作按钮
                HStack(spacing: 20) {
                    Button(action: {
                        onInteraction()
                        onTogglePlayback()
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: scaled(28), weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }
                    .disabled(!isPlayEnabled)
                }
            }
            .padding(.bottom, 30)
            .padding(.leading, 60)
            .padding(.trailing, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // 顶部控制栏（横屏 top-right -> 用户横屏 top-right）：更多按钮 + 播放设置面板
            VStack(alignment: .trailing, spacing: 12) {
                // 更多按钮（三白点图标）
                Button(action: {
                    isSettingsPanelVisible.toggle()
                    onInteraction()
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: scaled(18), weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                        .frame(width: scaled(36), height: scaled(36))
                }

                // 播放设置面板（点击更多按钮展开/收起）
                if isSettingsPanelVisible {
                    VStack(alignment: .leading, spacing: 0) {
                        // 标题行
                        HStack {
                            Text("播放设置")
                                .font(.system(size: scaled(14), weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { isSettingsPanelVisible = false; onInteraction() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: scaled(11), weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: scaled(24), height: scaled(24))
                                    .background(Circle().fill(Color.white.opacity(0.15)))
                            }
                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.top, scaled(12))
                        .padding(.bottom, scaled(10))

                        // 分割线
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.horizontal, scaled(14))

                        // 图标按钮区
                        HStack(spacing: scaled(16)) {
                            settingsIconButton(
                                icon: eyeProtectionEnabled ? "eye.fill" : "eye",
                                label: "护眼模式",
                                isActive: eyeProtectionEnabled
                            ) { onToggleEyeProtection(); onInteraction() }

                            settingsIconButton(
                                icon: "arrow.up.left.and.arrow.down.right",
                                label: "撑满全屏",
                                isActive: fillScreenEnabled
                            ) { onToggleFillScreen(); onInteraction() }

                            settingsIconButton(
                                icon: animationStyle == .rightToLeft ? "arrow.left" : "arrow.down",
                                label: animationStyle == .rightToLeft ? "左右翻页" : "上下翻页",
                                isActive: true
                            ) { onToggleAnimationStyle(); onInteraction() }

                            settingsIconButton(
                                icon: "xmark.circle",
                                label: "关闭",
                                isActive: true,
                                activeColor: .red
                            ) { onDismiss() }
                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.vertical, scaled(14))

                        // 分割线
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.horizontal, scaled(14))

                        // 播完本集 Toggle 行
                        HStack {
                            Text("播完本集")
                                .font(.system(size: scaled(13)))
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { onToggleAutoStop(); onInteraction() }) {
                                RoundedRectangle(cornerRadius: scaled(12))
                                    .fill(autoStopEnabled ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: scaled(40), height: scaled(24))
                                    .overlay(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: scaled(20), height: scaled(20))
                                            .offset(x: autoStopEnabled ? scaled(8) : -scaled(8))
                                            .animation(.easeInOut(duration: 0.15), value: autoStopEnabled)
                                    )
                            }
                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.vertical, scaled(10))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: scaled(12))
                            .fill(Color.black.opacity(0.25))
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
                }
            }
            .padding(.trailing, 60)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .animation(.easeInOut(duration: 0.2), value: isSettingsPanelVisible)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var settingsIconSize: CGFloat { scaled(42) }
    private var settingsIconFontSize: CGFloat { scaled(20) }
    private var settingsLabelFontSize: CGFloat { scaled(11) }

    @ViewBuilder
    private func settingsIconButton(icon: String, label: String, isActive: Bool, activeColor: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: scaled(6)) {
                Image(systemName: icon)
                    .font(.system(size: settingsIconFontSize))
                    .foregroundColor(isActive ? activeColor : .white.opacity(0.4))
                    .frame(width: settingsIconSize, height: settingsIconSize)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isActive ? 0.15 : 0.08))
                    )
                Text(label)
                    .font(.system(size: settingsLabelFontSize))
                    .foregroundColor(isActive ? .white : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(width: settingsIconSize)
        }
    }
}

// MARK: - 播放器图片渲染（无手势，手势由外层统一处理）

private struct PlayerImageView: View {
    let sessionId: String?
    let preloadedImages: [UIImage]?
    let index: Int
    let size: CGSize
    var fillScreen: Bool = false

    @State private var loadedImage: UIImage? = nil
    private static let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension

    private var displayImage: UIImage? {
        if let images = preloadedImages, index < images.count {
            return images[index]
        }
        return loadedImage
    }

    var body: some View {
        ZStack {
            if let img = displayImage {
                // 模糊背景
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(Constants.ImageDisplay.blurBackgroundScaleEffect)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: Constants.ImageDisplay.blurBackgroundRadius)
                    .opacity(Constants.ImageDisplay.blurBackgroundOpacity)
                    .clipped()
                // 主图：撑满全屏时 .fit 拉伸填满，否则以原尺寸展示（不放大，仅缩小以适屏）
                if fillScreen {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: min(size.width, img.size.width),
                            maxHeight: min(size.height, img.size.height)
                        )
                        .cornerRadius(8)
                }
            } else {
                Color.clear
                    .overlay { ProgressView() }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onAppear { loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard preloadedImages == nil, loadedImage == nil, let sid = sessionId else { return }
        if let cached = SessionRecordManager.shared.loadImageIfCached(sessionId: sid, index: index, maxDimension: Self.maxDim) {
            loadedImage = cached
            return
        }
        let idx = index
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: Self.maxDim)
            DispatchQueue.main.async {
                guard index == idx else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    loadedImage = loaded
                }
            }
        }
    }
}

// MARK: - 播放器进度条（纯轨道，时间标签由 PlayerControlLayer 外置）

private struct PlayerProgressBar: View {
    let progress: Double
    let segmentRatios: [Double]
    let isDraggable: Bool
    let onSeek: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0.0

    private var displayProgress: Double {
        isDragging ? dragProgress : progress
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width
            let barH = Constants.Playback.progressBarHeight
            let thumbSz = Constants.Playback.progressBarThumbSize

            ZStack(alignment: .leading) {
                // 轨道背景
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: barH)
                    .frame(maxWidth: .infinity)

                // 已播放填充
                Capsule()
                    .fill(Constants.Playback.progressBarFillColor)
                    .frame(width: max(0, barWidth * displayProgress), height: barH)

                // 分割点标记
                ForEach(Array(segmentRatios.enumerated()), id: \.offset) { _, ratio in
                    if ratio > 0.02 && ratio < 0.98 {
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: Constants.Playback.segmentDotSize, height: Constants.Playback.segmentDotSize)
                            .position(x: barWidth * ratio, y: thumbSz / 2)
                    }
                }

                // 当前位置滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSz, height: thumbSz)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(
                        x: max(thumbSz / 2, min(barWidth - thumbSz / 2, barWidth * displayProgress)),
                        y: thumbSz / 2
                    )
            }
            .frame(height: thumbSz)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isDraggable else { return }
                        isDragging = true
                        dragProgress = max(0, min(1, value.location.x / max(1, barWidth)))
                    }
                    .onEnded { value in
                        guard isDraggable else { isDragging = false; return }
                        isDragging = false
                        let rawRatio = max(0, min(1, value.location.x / max(1, barWidth)))
                        let snapped = snapToNearestSegment(rawRatio)
                        onSeek(snapped)
                    }
            )
            .allowsHitTesting(isDraggable)
        }
        .frame(height: Constants.Playback.progressBarThumbSize)
    }

    private func snapToNearestSegment(_ ratio: Double) -> Double {
        guard !segmentRatios.isEmpty else { return ratio }
        return segmentRatios.min(by: { abs($0 - ratio) < abs($1 - ratio) }) ?? ratio
    }
}

// MARK: - 全屏大图内容（其他页面使用，PlayView 不再使用）
struct FullScreenImageContent<Overlay: View>: View {
    /// 会话 ID，非空时按 index 从 SessionRecordManager 按需加载
    var sessionId: String? = nil
    var totalImageCount: Int = 0
    /// 预加载图（如制作中未保存的会话），非空时优先使用
    var preloadedImages: [UIImage]? = nil
    @Binding var currentIndex: Int
    var onTapBackground: (() -> Void)? = nil
    var onDoubleTapBackground: (() -> Void)? = nil
    var isSwipeDisabled: Bool = false
    @ViewBuilder let overlayContent: () -> Overlay

    /// 兼容旧用法：直接传入图片数组（如 App 内全屏看图）
    init(images: [UIImage], currentIndex: Binding<Int>, isSwipeDisabled: Bool = false, onTapBackground: (() -> Void)? = nil, onDoubleTapBackground: (() -> Void)? = nil, @ViewBuilder overlayContent: @escaping () -> Overlay) {
        self.sessionId = nil
        self.totalImageCount = images.count
        self.preloadedImages = images
        self._currentIndex = currentIndex
        self.isSwipeDisabled = isSwipeDisabled
        self.onTapBackground = onTapBackground
        self.onDoubleTapBackground = onDoubleTapBackground
        self.overlayContent = overlayContent
    }

    init(sessionId: String? = nil, totalImageCount: Int = 0, preloadedImages: [UIImage]? = nil, currentIndex: Binding<Int>, isSwipeDisabled: Bool = false, onTapBackground: (() -> Void)? = nil, onDoubleTapBackground: (() -> Void)? = nil, @ViewBuilder overlayContent: @escaping () -> Overlay) {
        self.sessionId = sessionId
        self.totalImageCount = totalImageCount
        self.preloadedImages = preloadedImages
        self._currentIndex = currentIndex
        self.isSwipeDisabled = isSwipeDisabled
        self.onTapBackground = onTapBackground
        self.onDoubleTapBackground = onDoubleTapBackground
        self.overlayContent = overlayContent
    }

    private var useOnDemand: Bool { sessionId != nil && totalImageCount > 0 }
    private var imageCount: Int {
        if useOnDemand { return totalImageCount }
        return preloadedImages?.count ?? 0
    }

    var body: some View {
        Group {
            if imageCount > 0 {
                CustomZStack(backgroundColor: Color.clear) {
                    Constants.Playback.eyeProtectionBackgroundColor
                        .ignoresSafeArea(.all)
                        .optionalDoubleTapGesture(onDoubleTapBackground)
                        .onTapGesture { onTapBackground?() }

                    if useOnDemand, let sid = sessionId {
                        GeometryReader { geometry in
                            OnDemandImagePage(sessionId: sid, index: currentIndex, size: geometry.size, onTap: onTapBackground, onDoubleTap: onDoubleTapBackground)
                                .id(currentIndex)
                                .transition(.opacity)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: Constants.Gesture.swipeMinDistance)
                                        .onEnded { value in
                                            guard !isSwipeDisabled else { return }
                                            let t = value.translation.width
                                            if t < -Constants.Gesture.swipeMinDistance {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    currentIndex = min(currentIndex + 1, imageCount - 1)
                                                }
                                            } else if t > Constants.Gesture.swipeMinDistance {
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    currentIndex = max(0, currentIndex - 1)
                                                }
                                            }
                                        }
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                        .onAppear {
                            preloadAdjacentImages(sessionId: sid, current: currentIndex, total: imageCount)
                        }
                        .onChange(of: currentIndex) { _, newIndex in
                            preloadAdjacentImages(sessionId: sid, current: newIndex, total: imageCount)
                        }
                    } else {
                        TabView(selection: $currentIndex) {
                            ForEach(0..<imageCount, id: \.self) { index in
                                GeometryReader { geometry in
                                    if let imgs = preloadedImages, index < imgs.count {
                                        singleImagePage(imgs[index], size: geometry.size)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay {
                            if isSwipeDisabled {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(DragGesture())
                            }
                        }
                    }
                    overlayContent()
                }
                .ignoresSafeArea(.all)
            }
        }
        .optionalDoubleTapGesture(onDoubleTapBackground)
        .onTapGesture { onTapBackground?() }
    }

    private func preloadAdjacentImages(sessionId: String, current: Int, total: Int) {
        let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension
        if current + 1 < total {
            SessionRecordManager.shared.preloadImage(sessionId: sessionId, index: current + 1, maxDimension: maxDim)
        }
        if current - 1 >= 0 {
            SessionRecordManager.shared.preloadImage(sessionId: sessionId, index: current - 1, maxDimension: maxDim)
        }
    }

    @ViewBuilder
    private func singleImagePage(_ image: UIImage, size: CGSize) -> some View {
        CustomZStack(backgroundColor: Color.clear) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(Constants.ImageDisplay.blurBackgroundScaleEffect)
                .frame(width: size.width, height: size.height)
                .blur(radius: Constants.ImageDisplay.blurBackgroundRadius)
                .opacity(Constants.ImageDisplay.blurBackgroundOpacity)
                .clipped()
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
                .optionalDoubleTapGesture(onDoubleTapBackground)
                .onTapGesture { onTapBackground?() }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// 加载单页图（FullScreenImageContent 使用）
private struct OnDemandImagePage: View {
    let sessionId: String
    let index: Int
    let size: CGSize
    var onTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    @State private var image: UIImage? = nil

    private static let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension

    var body: some View {
        CustomZStack(backgroundColor: Color.clear) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(Constants.ImageDisplay.blurBackgroundScaleEffect)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: Constants.ImageDisplay.blurBackgroundRadius)
                    .opacity(Constants.ImageDisplay.blurBackgroundOpacity)
                    .clipped()
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .optionalDoubleTapGesture(onDoubleTap)
                    .onTapGesture { onTap?() }
            } else {
                Color.clear
                    .overlay { ProgressView() }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onAppear {
            if image == nil {
                if let cached = SessionRecordManager.shared.loadImageIfCached(sessionId: sessionId, index: index, maxDimension: Self.maxDim) {
                    image = cached
                    return
                }
                let sid = sessionId
                let idx = index
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: Self.maxDim)
                    DispatchQueue.main.async {
                        guard index == idx else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            image = loaded
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 仅在 handler 非空时添加双击手势，避免对单击手势引入识别延迟
private extension View {
    @ViewBuilder
    func optionalDoubleTapGesture(_ handler: (() -> Void)?) -> some View {
        if let handler = handler {
            self.onTapGesture(count: 2, perform: handler)
        } else {
            self
        }
    }
}
