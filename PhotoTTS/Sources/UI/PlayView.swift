import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import os.log

// MARK: - 控制条类型

/// 控制条类型
private enum ControlBarType {
    case volume
    case brightness
}

/// 手势拖拽模式
private enum DragMode {
    case undecided
    case adjustControl
    case swipePage
}

// MARK: - 播放器

/// 竖屏播放器：图片保持拍摄原始方向，全屏展示。
/// 操作控件（播控、进度条、控制栏）悬浮在图片之上。
/// 图片切换由音频进度自动驱动（播放中），或由用户拖动进度条手动控制（暂停时）。
struct PlayView: View {
    var recordId: String? = nil
    var preloadedRecord: SessionRecord? = nil
    var queueRecordIds: [String] = []  // 连播队列（含自身）
    let onDismiss: () -> Void

    @State private var record: SessionRecord?
    // 连播状态
    @State private var currentQueueIndex: Int = 0
    @State private var isTransitioning: Bool = false
    @State private var nextRecordName: String = ""
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
    /// 制作页传入的预加载图片（已废弃，改用 preloadedImageDataList 按需解码）
    @State private var preloadedImages: [UIImage]? = nil
    /// 制作页传入的 Base64 图片数据列表，用于按需解码
    @State private var preloadedImageDataList: [String]? = nil
    @State private var isOverlayVisible = false
    @State private var overlayAutoHideTimer: Timer?
    /// "同日连播"开关，默认开启（队列有下一条时自动连播）
    @State private var continuousPlayEnabled = true
    /// 护眼模式：开启时使用护眼绿背景，关闭时使用黑色背景
    @State private var eyeProtectionEnabled = true
    /// 撑满全屏：开启时图片 .fit 拉伸填满可用空间（现有行为），关闭时以原尺寸展示（不放大，仅缩小以适屏）
    @State private var fillScreenEnabled = true
    /// 翻页动画样式：从右到左（默认）或从上到下（相对横屏控制层）
    @State private var animationStyle: AnimationStyle = .rightToLeft
    /// 翻页方向：true=正向(index增大)，false=反向(index减小)，用于动态控制 transition 方向
    @State private var isForwardTransition: Bool = true
    /// 控制条类型
    @State private var controlBarType: ControlBarType?
    /// 控制条当前值（0.0~1.0）
    @State private var controlBarValue: CGFloat = 0.0
    /// 控制条自动隐藏定时器
    @State private var controlBarAutoHideTimer: Timer?
    /// 手势拖拽模式
    @State private var dragMode: DragMode = .undecided
    /// 当前调节的控制类型
    @State private var activeControlType: ControlBarType? = nil
    /// 手势开始时的控制值
    @State private var controlStartValue: CGFloat = 0
    /// 手势开始时的拖拽位移（消除初始跳变）
    @State private var controlStartTranslation: CGFloat = 0
    /// 系统音量滑块（隐藏，用于编程控制系统音量）
    @State private var systemVolumeSlider: UISlider? = nil
    /// 播放倍速
    @State private var playbackSpeed: Constants.PlaybackSpeed = .x1


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

    /// 图片索引上限：有要点图片时为 totalImageCount（要点图片索引），否则为 totalImageCount - 1
    private var maxImageIndex: Int {
        guard let r = record else { return 0 }
        // 兼容存量记录：hasVirtualPage 或 storyHighlights 存在即为有要点图片
        let hasHighlightsPage = r.hasVirtualPage || r.storyHighlights != nil
        if hasHighlightsPage && r.id != Constants.DefaultSession.id {
            return r.totalImageCount
        }
        return max(0, r.totalImageCount - 1)
    }

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
            loadPlaybackSpeed()  // 加载持久化的倍速设置
            if let pre = preloadedRecord {
                record = pre
                recordIsFromPreload = true
                // 使用 imageDataList 按需解码，避免 getImages() 全量解码
                preloadedImages = nil
                preloadedImageDataList = pre.imageDataList.isEmpty ? nil : pre.imageDataList
                textSegmentRanges = computeTextSegmentRanges(pre.ocrTextSegments)
                animationStyle = pre.animationStyle
                isLoading = false
                // 要点图片由 PlayerImageView 按需加载，无需在此处理
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
            controlBarAutoHideTimer?.invalidate()
            controlBarAutoHideTimer = nil
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
        // E2E传输：接收方公共 UI + 暂停播放回调
        .transferReceiver(isActive: true, onInvitationReceived: { pauseIfPlaying() })
    }

    // MARK: - 播放器主视图

    @ViewBuilder
    private func playerView(record: SessionRecord) -> some View {
        GeometryReader { geometry in
            ZStack {
                // 底层：护眼底色 + 手势区域
                GeometryReader { gestureGeometry in
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
                        // 手势识别：音量亮度调节 + 翻页切换（合并为单一手势，按方向区分）
                        // 竖屏 width 方向 = 横屏上下滑 = 音量/亮度调节（连续比例）
                        // 竖屏 height 方向 = 横屏左右滑 = 翻页切换（仅暂停时）
                        .simultaneousGesture(
                            DragGesture(minimumDistance: Constants.Gesture.gestureMinDragDistance)
                                .onChanged { value in
                                    // 控制层可见时禁止底层拖拽，避免与进度条手势冲突
                                    guard !isOverlayVisible else { return }
                                    // 首次超过阈值时确定手势模式
                                    if dragMode == .undecided {
                                        let absW = abs(value.translation.width)
                                        let absH = abs(value.translation.height)
                                        // 判断主方向
                                        if absW >= absH {
                                            // 竖屏水平方向 = 横屏上下滑 = 音量/亮度
                                            // 特例：暂停时 topToBottom 翻页也使用此方向，翻页优先
                                            if !isPlaying && animationStyle == .topToBottom {
                                                dragMode = .swipePage
                                            } else {
                                                dragMode = .adjustControl
                                                let centerY = gestureGeometry.size.height / 2
                                                let isLeftSide = value.startLocation.y < centerY
                                                activeControlType = isLeftSide ? .brightness : .volume
                                                controlStartValue = isLeftSide
                                                    ? UIScreen.main.brightness
                                                    : CGFloat(AVAudioSession.sharedInstance().outputVolume)
                                                controlStartTranslation = value.translation.width
                                            }
                                        } else {
                                            // 竖屏垂直方向 = 横屏左右滑 = 翻页
                                            dragMode = .swipePage
                                        }
                                    }
                                    // 音量/亮度：连续比例调节（半屏拖拽 = 0~100%）
                                    if dragMode == .adjustControl, let control = activeControlType {
                                        let halfScreen = gestureGeometry.size.width * 0.5
                                        let dragDistance = value.translation.width - controlStartTranslation
                                        // width 正值 = 横屏上滑 = 增大
                                        let normalizedDelta = dragDistance / halfScreen
                                        let newValue = max(0, min(1, controlStartValue + normalizedDelta))
                                        switch control {
                                        case .brightness:
                                            UIScreen.main.brightness = newValue
                                            controlBarType = .brightness
                                            controlBarValue = newValue
                                        case .volume:
                                            setSystemVolume(Float(newValue))
                                            controlBarType = .volume
                                            controlBarValue = newValue
                                        }
                                        startControlBarAutoHideTimer()
                                    }
                                }
                                .onEnded { value in
                                    // 控制层可见时禁止底层拖拽，避免与进度条手势冲突
                                    guard !isOverlayVisible else {
                                        dragMode = .undecided
                                        activeControlType = nil
                                        return
                                    }
                                    let prevMode = dragMode
                                    dragMode = .undecided
                                    activeControlType = nil
                                    if prevMode == .adjustControl {
                                        startControlBarAutoHideTimer()
                                        return
                                    }
                                    // 翻页：仅暂停时生效
                                    guard !isPlaying, audioPlayer != nil else { return }
                                    let newIndex: Int
                                    switch animationStyle {
                                    case .rightToLeft:
                                        // 竖屏 height- = 用户横屏左滑 -> 下一张
                                        let t = value.translation.height
                                        if t < -Constants.Gesture.swipeMinDistance {
                                            newIndex = min(currentImageIndex + 1, maxImageIndex)
                                        } else if t > Constants.Gesture.swipeMinDistance {
                                            newIndex = max(0, currentImageIndex - 1)
                                        } else {
                                            return
                                        }
                                    case .topToBottom:
                                        // 竖屏 width+ = 用户横屏上滑 -> 上一张
                                        let t = value.translation.width
                                        if t > Constants.Gesture.swipeMinDistance {
                                            newIndex = max(0, currentImageIndex - 1)
                                        } else if t < -Constants.Gesture.swipeMinDistance {
                                            newIndex = min(currentImageIndex + 1, maxImageIndex)
                                        } else {
                                            return
                                        }
                                    }
                                    guard newIndex != currentImageIndex else { return }
                                    isForwardTransition = newIndex > currentImageIndex
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentImageIndex = newIndex
                                    }
                                    if newIndex < segmentRatios.count {
                                        seekToRatio(segmentRatios[newIndex])
                                    }
                                }
                        )
                }

                // 图片层（不响应手势，传递给底层）
                PlayerImageView(
                    sessionId: recordIsFromPreload ? nil : record.id,
                    preloadedImages: nil, // 已废弃，改用 imageDataList 按需解码
                    imageDataList: recordIsFromPreload ? preloadedImageDataList : nil,
                    index: currentImageIndex,
                    size: geometry.size,
                    fillScreen: fillScreenEnabled,
                    totalImageCount: record.totalImageCount,
                    hasVirtualPage: record.hasVirtualPage,
                    storyHighlights: record.storyHighlights,
                    animationStyle: animationStyle,
                    isDefaultSession: record.id == Constants.DefaultSession.id
                )
                .id("\(record.id)_\(currentImageIndex)")
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
                        continuousPlayEnabled: continuousPlayEnabled,
                        showProgressBar: audioPlayer != nil,
                        isPlayEnabled: record.getAudioData() != nil,
                        playbackProgress: playbackProgress,
                        currentAudioTime: currentAudioTime,
                        totalAudioDuration: totalAudioDuration,
                        segmentRatios: segmentRatios,
                        isDraggable: true,
                        eyeProtectionEnabled: eyeProtectionEnabled,
                        fillScreenEnabled: fillScreenEnabled,
                        animationStyle: $animationStyle,
                        playbackSpeed: playbackSpeed,
                        onTogglePlayback: { togglePlayback() },
                        onToggleContinuousPlay: { continuousPlayEnabled.toggle() },
                        onToggleEyeProtection: { eyeProtectionEnabled.toggle() },
                        onToggleFillScreen: { fillScreenEnabled.toggle() },
                        onToggleAnimationStyle: {
                            animationStyle = animationStyle == .rightToLeft ? .topToBottom : .rightToLeft
                        },
                        onToggleSpeed: { togglePlaybackSpeed($0) },
                        onDismiss: { stopAndDismiss() },
                        onHideOverlay: { isOverlayVisible = false },
                        onSeek: { seekToRatio($0) },
                        onInteraction: { startOverlayAutoHideTimer() },
                        showNextButton: currentQueueIndex + 1 < queueRecordIds.count,
                        currentQueueIndex: currentQueueIndex,
                        totalQueueCount: queueRecordIds.count,
                        onNextRecord: {
                            // 停止当前播放，切换到下一条
                            audioPlayer?.stop()
                            playbackTimer?.invalidate()
                            playbackTimer = nil
                            isPlaying = false
                            PlayHistoryManager.shared.recordPlay(sessionId: record.id, name: record.name, playedAt: Date())
                            advanceToNextRecord()
                        }
                    )
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    // 手势隔离：整个控制层区域拦截触摸，防止穿透到底层触发翻页/单击
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
                }

                // 控制条（横屏顶部，+90°旋转到横屏坐标系）
                if let barType = controlBarType {
                    volumeBrightnessControlBar(
                        type: barType,
                        value: controlBarValue,
                        landscapeWidth: geometry.size.height
                    )
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                // 连播过渡页面（横屏布局，旋转 +90° 适配横屏观看）
                if isTransitioning {
                    ZStack {
                        Color(.systemBackground).opacity(0.95)
                        VStack(spacing: 16) {
                            Text("\(currentQueueIndex + 2)/\(queueRecordIds.count)：\(nextRecordName)")
                                .font(Constants.Fonts.body)
                                .foregroundColor(.primary)
                            ProgressView()
                        }
                    }
                    .frame(width: geometry.size.height, height: geometry.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.3), value: currentImageIndex)
        .animation(.easeInOut(duration: 0.3), value: isTransitioning)
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
                animationStyle = loaded.animationStyle
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
        let separatorCount = Constants.ocrTextSeparator.count
        for (index, segment) in segments.enumerated() {
            let start = pos
            pos += segment.count
            if index < segments.count - 1 {
                pos += separatorCount
            }
            ranges.append((start, pos))
        }
        return ranges
    }

    // MARK: - 倍速管理

    /// 从 UserDefaults 读取持久化的倍速设置
    private func loadPlaybackSpeed() {
        if let savedRaw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.playbackSpeed),
           let speed = Constants.PlaybackSpeed(rawValue: savedRaw) {
            playbackSpeed = speed
        } else {
            playbackSpeed = .default
        }
    }

    /// 保存倍速设置到 UserDefaults
    private func savePlaybackSpeed(_ speed: Constants.PlaybackSpeed) {
        UserDefaults.standard.set(speed.rawValue, forKey: Constants.UserDefaultsKeys.playbackSpeed)
    }

    /// 切换播放倍速
    private func togglePlaybackSpeed(_ speed: Constants.PlaybackSpeed) {
        playbackSpeed = speed
        savePlaybackSpeed(speed)
        audioPlayer?.rate = speed.rate
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
            player.enableRate = true  // 启用变速播放
            guard player.prepareToPlay(), player.play() else { return }
            player.rate = playbackSpeed.rate  // 设置当前倍速
            audioPlayer = player
            audioPlayerDelegate = delegate
            isPlaying = true
            playbackProgress = 0
            startPlaybackTimer()
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
                if index != currentImageIndex && index <= maxImageIndex {
                    isForwardTransition = index > currentImageIndex
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentImageIndex = index
                    }
                }
                return
            }
        }
        if progress >= 1.0, !textSegmentRanges.isEmpty {
            currentImageIndex = min(textSegmentRanges.count - 1, maxImageIndex)
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
    }

    private func pauseIfPlaying() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        playbackTimer?.invalidate()
    }

    private func onPlaybackFinished() {
        isPlaying = false
        playbackProgress = 1.0
        playbackTimer?.invalidate()
        playbackTimer = nil
        clearRemoteTransportControls()
        if let r = record {
            PlayHistoryManager.shared.recordPlay(sessionId: r.id, name: r.name, playedAt: Date())
        }
        if !continuousPlayEnabled {
            // 关闭"同日连播"：当前记录播完即退出，不继续连播
            stopAndDismiss()
        } else if currentQueueIndex + 1 < queueRecordIds.count {
            // 开启"同日连播"且队列有下一条：自动连播
            advanceToNextRecord()
        } else {
            // 开启"同日连播"但队列已播完：自动退出播放器
            stopAndDismiss()
        }
    }

    // MARK: - 连播切换

    /// 切换到队列中的下一条记录
    private func advanceToNextRecord() {
        let nextIndex = currentQueueIndex + 1
        guard nextIndex < queueRecordIds.count else {
            stopAndDismiss()
            return
        }

        let nextId = queueRecordIds[nextIndex]

        // 获取下一条记录名称用于过渡页面
        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "PlayView.连播过渡")
        nextRecordName = allMetadata.first(where: { $0.id == nextId })?.name ?? ""

        isTransitioning = true
        stopAudio()

        // 预加载下一条记录
        let transitionStart = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let nextRecord = SessionRecordManager.shared.loadSession(id: nextId)

            DispatchQueue.main.async {
                guard isTransitioning else { return }

                guard let nextRecord = nextRecord else {
                    // 加载失败，跳过尝试下一条
                    os.Logger.audioPlayer.warning("连播: 跳过加载失败的记录 id=\(nextId)")
                    currentQueueIndex = nextIndex
                    isTransitioning = false
                    advanceToNextRecord()
                    return
                }

                // 确保过渡页面至少显示 5 秒
                let elapsed = Date().timeIntervalSince(transitionStart)
                let remainingDelay = max(0, Constants.Playback.transitionMinDisplayDuration - elapsed)

                DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                    guard isTransitioning else { return }

                    // 切换到新记录
                    currentQueueIndex = nextIndex
                    record = nextRecord
                    recordIsFromPreload = false
                    preloadedImages = nil
                    preloadedImageDataList = nil
                    textSegmentRanges = computeTextSegmentRanges(nextRecord.ocrTextSegments)
                    animationStyle = nextRecord.animationStyle
                    currentImageIndex = 0
                    playbackProgress = 0.0
                    isTransitioning = false

                    if nextRecord.getAudioData() != nil {
                        startPlayback()
                    }
                }
            }
        }
    }

    private func stopAudio() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil
        clearRemoteTransportControls()
    }

    private func stopAndDismiss() {
        isTransitioning = false
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

    // MARK: - 控制条自动隐藏

    private func startControlBarAutoHideTimer() {
        controlBarAutoHideTimer?.invalidate()
        controlBarAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    controlBarType = nil
                }
            }
        }
    }

    // MARK: - 系统音量控制

    /// 通过隐藏的 MPVolumeView 设置系统音量并抑制系统 HUD
    /// MPVolumeView 必须在视图层级中且 isHidden=false 才能抑制系统音量提示
    private func setSystemVolume(_ value: Float) {
        if systemVolumeSlider == nil {
            let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
            volumeView.alpha = 0.001 // 不使用 isHidden，确保能抑制系统 HUD
            // 添加到 window 使其生效并抑制系统音量 HUD
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.addSubview(volumeView)
            }
            // 提取内部 UISlider
            for subview in volumeView.subviews {
                if let slider = subview as? UISlider {
                    systemVolumeSlider = slider
                    break
                }
            }
        }
        systemVolumeSlider?.value = max(0, min(1, value))
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

    // MARK: - 音量亮度控制条

    /// 音量亮度控制条组件（横屏坐标系布局，旋转由调用方处理）
    @ViewBuilder
    private func volumeBrightnessControlBar(type: ControlBarType, value: CGFloat, landscapeWidth: CGFloat) -> some View {
        let icon: String = switch type {
        case .volume:
            value > 0.5 ? "speaker.wave.2.fill" : (value > 0 ? "speaker.wave.1.fill" : "speaker.slash.fill")
        case .brightness:
            "sun.max.fill"
        }

        let barHeight: CGFloat = scaled(4)
        let barMaxWidth: CGFloat = landscapeWidth * 0.325
        let currentBarWidth: CGFloat = max(0, barMaxWidth * value)

        // 横屏坐标系：顶部居中控制条
        VStack {
            HStack(spacing: scaled(10)) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: scaled(16), height: scaled(16))
                    .foregroundColor(.white)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: barMaxWidth, height: barHeight)
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(Color.white)
                        .frame(width: currentBarWidth, height: barHeight)
                }
            }
            .padding(.horizontal, scaled(40))
            .padding(.top, scaled(12))

            Spacer()
        }
    }
}

// MARK: - 播放器控制层（横屏布局，旋转 +90° 覆盖在竖屏图片之上）

/// 横屏播放器控制层：内部按横屏布局（宽>高），由 PlayView 旋转 +90° 后叠加在竖屏图片之上。
/// 旋转映射（+90° CW，适配手机左侧为底的横屏观看）：横屏 bottom-left -> 竖屏 top-left -> 用户横屏 bottom-left，
/// 横屏 top-right -> 竖屏 bottom-right -> 用户横屏 top-right。HStack 内左→右顺序在用户横屏视角下保持不变。
private struct PlayerControlLayer: View {
    let isPlaying: Bool
    let continuousPlayEnabled: Bool
    let showProgressBar: Bool
    let isPlayEnabled: Bool
    let playbackProgress: Double
    let currentAudioTime: TimeInterval
    let totalAudioDuration: TimeInterval
    let segmentRatios: [Double]
    let isDraggable: Bool
    let eyeProtectionEnabled: Bool
    let fillScreenEnabled: Bool
    @Binding var animationStyle: AnimationStyle
    let playbackSpeed: Constants.PlaybackSpeed
    let onTogglePlayback: () -> Void
    let onToggleContinuousPlay: () -> Void
    let onToggleEyeProtection: () -> Void
    let onToggleFillScreen: () -> Void
    let onToggleAnimationStyle: () -> Void
    let onToggleSpeed: (Constants.PlaybackSpeed) -> Void
    let onDismiss: () -> Void
    let onHideOverlay: () -> Void
    let onSeek: (Double) -> Void
    let onInteraction: () -> Void
    var showNextButton: Bool = false
    var currentQueueIndex: Int = 0
    var totalQueueCount: Int = 1
    var onNextRecord: () -> Void = {}

    @State private var isSettingsPanelVisible = false
    private var playButtonSize: CGFloat { scaled(25) }
    private var controlButtonSize: CGFloat { scaled(40) }

    /// 设备自适应缩放快捷方法（iPhone 返回原值，iPad 按比例放大）
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ZStack {
            // 横屏 bottom-left（旋转后 -> 用户横屏 bottom-left）：时间 + 进度条 + 操作按钮 + 设置按钮
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
                    .font(Constants.Fonts.playTimerText)
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

                // 操作按钮（含设置按钮）
                HStack(spacing: 20) {
                    Button(action: {
                        onInteraction()
                        onTogglePlayback()
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(Constants.Fonts.playMainIcon)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }
                    .disabled(!isPlayEnabled)

                    // 下一个按钮（连播队列中有下一条时显示）
                    if showNextButton {
                        Button(action: {
                            onInteraction()
                            onNextRecord()
                        }) {
                            Image(systemName: "forward.end.fill")
                                .font(Constants.Fonts.playMainIcon)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                        }

                        // 连播进度
                        Text(" (\(currentQueueIndex + 1)/\(totalQueueCount))")
                            .font(Constants.Fonts.playQueueProgress)
                            .foregroundColor(.white.opacity(0.5))
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }

                    Spacer()

                    // 设置按钮（与播放按钮同一水平线）
                    Button(action: {
                        isSettingsPanelVisible.toggle()
                        onInteraction()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(Constants.Fonts.playSetIcon)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    }

                    // 关闭按钮（与设置按钮同一水平线）
                    Button(action: {
                        onDismiss()
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(Constants.Fonts.playMoreIcon)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                            //.frame(width: scaled(36), height: scaled(36))
                    }
                }
            }
            .padding(.bottom, 30)
            .padding(.leading, 60)
            .padding(.trailing, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // 右侧：播放设置面板（从右边缘弹出，top/right 贴紧屏幕边缘）
            if isSettingsPanelVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 标题行
                        HStack {
                            Text("播放设置")
                                .font(Constants.Fonts.playSettingsTitle)
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { isSettingsPanelVisible = false; onInteraction() }) {
                                Image(systemName: "xmark")
                                    .font(Constants.Fonts.playCloseIcon)
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

                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.vertical, scaled(14))

                        // 分割线
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.horizontal, scaled(14))

                        // 倍速选择区域
                        VStack(alignment: .leading, spacing: scaled(8)) {
                            Text("倍速")
                                .font(Constants.Fonts.playNextLabel)
                                .foregroundColor(.white)

                            // 倍速选项网格布局：每行3个按钮
                            let columns = Array(repeating: GridItem(.fixed(scaled(44)), spacing: scaled(8)), count: 3)

                            LazyVGrid(columns: columns, spacing: scaled(8)) {
                                ForEach(Constants.PlaybackSpeed.allCases, id: \.self) { speed in
                                    Button(action: {
                                        onToggleSpeed(speed)
                                        onInteraction()
                                    }) {
                                        Text(speed.displayName)
                                            .font(Constants.Fonts.playSettingsLabel)
                                            .foregroundColor(playbackSpeed == speed ? .white : .white.opacity(0.5))
                                            .frame(width: scaled(44), height: scaled(28))
                                            .background(
                                                RoundedRectangle(cornerRadius: scaled(6))
                                                    .fill(playbackSpeed == speed ? Color.white.opacity(0.25) : Color.clear)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: scaled(6))
                                                    .stroke(Color.white.opacity(playbackSpeed == speed ? 0.5 : 0.2), lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.vertical, scaled(10))

                        // 分割线
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 0.5)
                            .padding(.horizontal, scaled(14))

                        // 同日连播 Toggle 行
                        HStack {
                            Text("同日连播")
                                .font(Constants.Fonts.playNextLabel)
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: { onToggleContinuousPlay(); onInteraction() }) {
                                RoundedRectangle(cornerRadius: scaled(12))
                                    .fill(continuousPlayEnabled ? Color.green : Color.gray.opacity(0.4))
                                    .frame(width: scaled(40), height: scaled(24))
                                    .overlay(
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: scaled(20), height: scaled(20))
                                            .offset(x: continuousPlayEnabled ? scaled(8) : -scaled(8))
                                            .animation(.easeInOut(duration: 0.15), value: continuousPlayEnabled)
                                    )
                            }
                        }
                        .padding(.horizontal, scaled(14))
                        .padding(.vertical, scaled(10))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: scaled(12))
                            .fill(Color.black.opacity(0.5))
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: scaled(350))
                .padding(.trailing, 0)
                .padding(.top, 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsPanelVisible)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var settingsIconSize: CGFloat { scaled(42) }
    private var settingsIconFontSize: Font { Constants.Fonts.recordActionIcon }
    private var settingsLabelFontSize: Font { Constants.Fonts.playSettingsLabel }

    @ViewBuilder
    private func settingsIconButton(icon: String, label: String, isActive: Bool, activeColor: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: scaled(6)) {
                Image(systemName: icon)
                    .font(settingsIconFontSize)
                    .foregroundColor(isActive ? activeColor : .white.opacity(0.4))
                    .frame(width: settingsIconSize, height: settingsIconSize)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(isActive ? 0.15 : 0.08))
                    )
                Text(label)
                    .font(settingsLabelFontSize)
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
    /// Base64 编码的图片数据列表，用于按需解码（替代 preloadedImages 全量解码）
    let imageDataList: [String]?
    let index: Int
    let size: CGSize
    var fillScreen: Bool = false
    var totalImageCount: Int? = nil
    var hasVirtualPage: Bool = false
    var storyHighlights: String? = nil
    var animationStyle: AnimationStyle = .rightToLeft
    var isDefaultSession: Bool = false

    @State private var loadedImage: UIImage? = nil
    @State private var highlightsImage: UIImage? = nil
    private static let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension

    /// 当前索引是否为要点图片页（兼容存量记录：hasVirtualPage 或 storyHighlights 存在即为 true）
    private var isHighlightsPage: Bool {
        guard let total = totalImageCount, !isDefaultSession else { return false }
        let hasHighlightsContent = hasVirtualPage || storyHighlights != nil
        guard hasHighlightsContent else { return false }
        return index >= total
    }

    private var displayImage: UIImage? {
        // 要点图片页：使用 EndPicts 图片
        if isHighlightsPage {
            return highlightsImage
        }
        // 真实图片：当索引超出预加载图片数量时，复用最后一张图片
        let effectiveIndex: Int
        if let total = totalImageCount {
            effectiveIndex = min(index, max(0, total - 1))
        } else {
            effectiveIndex = min(index, (preloadedImages?.count ?? imageDataList?.count ?? Int.max) - 1)
        }
        if let images = preloadedImages, effectiveIndex >= 0, effectiveIndex < images.count {
            return images[effectiveIndex]
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
        // 要点图片页：从合并池加载 EndPicts 图片
        if isHighlightsPage {
            guard highlightsImage == nil else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = SessionRecordManager.shared.loadEndPict(
                    animationStyle: animationStyle,
                    maxDimension: Self.maxDim
                )
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        highlightsImage = loaded
                    }
                }
            }
            return
        }

        // 已有预加载图片，无需再加载
        guard preloadedImages == nil, loadedImage == nil else { return }

        // 优先从 imageDataList 按需解码（制作页未保存会话）
        if let dataList = imageDataList, index >= 0, index < dataList.count {
            let idx = index
            DispatchQueue.global(qos: .userInitiated).async {
                // 直接从 Base64 解码，使用 Image I/O 降采样
                guard let data = Data(base64Encoded: dataList[idx]),
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    DispatchQueue.main.async { loadedImage = nil }
                    return
                }
                let maxPixel = Int(Self.maxDim * max(1, UIScreen.main.scale))
                let options: [CFString: Any] = [
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel
                ]
                let loaded: UIImage?
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    loaded = UIImage(cgImage: cgImage)
                } else if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    loaded = UIImage(cgImage: cgImage)
                } else {
                    loaded = nil
                }
                DispatchQueue.main.async {
                    guard index == idx else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        loadedImage = loaded
                    }
                }
            }
            return
        }

        // 从文件系统按需加载
        guard let sid = sessionId else { return }
        // 使用播放专用方法，自动处理要点图片页（索引超出时复用最后一张图片）
        if let cached = SessionRecordManager.shared.loadImageIfCached(sessionId: sid, index: index, maxDimension: Self.maxDim) {
            loadedImage = cached
            return
        }
        let idx = index
        DispatchQueue.global(qos: .userInitiated).async {
            // 播放时使用支持要点图片页的方法
            let loaded = SessionRecordManager.shared.loadImageForPlayback(
                sessionId: sid,
                index: idx,
                maxDimension: Self.maxDim,
                totalImageCount: self.totalImageCount ?? 0
            )
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
            .highPriorityGesture(
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
