import SwiftUI
import UIKit
import AVFoundation
import os.log

/// 播放视图
struct PlayView: View {
    var recordId: String? = nil
    var preloadedRecord: SessionRecord? = nil
    let onDismiss: () -> Void
    
    @State private var record: SessionRecord?
    /// 仅当从制作页传入的 preloadedRecord 时为 true；从 recordId 加载的会话一律按需加载，不调用 getImages()
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
    @State private var isOverlayVisible = false  // 点击全屏图切换操作栏显隐，起始不展示
    @State private var overlayAutoHideTimer: Timer?  // 5 秒无操作自动隐藏操作栏
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let overlayAutoHideInterval: TimeInterval = 5
    private var playButtonSize: CGFloat { isPad ? 28 : 25 }
    private var thumbSize: CGFloat { isPad ? 44 : 40 }
    
    var body: some View {
        Group {
            if isLoading {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    ProgressView("加载中...")
                }
            } else if let record = record, record.totalImageCount > 0 {
                let useOnDemand = !recordIsFromPreload
                FullScreenImageContent(
                    sessionId: useOnDemand ? record.id : nil,
                    totalImageCount: record.totalImageCount,
                    preloadedImages: useOnDemand ? nil : record.getImages(),
                    currentIndex: $currentImageIndex,
                    onTapBackground: {
                        isOverlayVisible.toggle()
                        if isOverlayVisible { startOverlayAutoHideTimer() }
                    },
                    overlayContent: {
                        if isOverlayVisible {
                            playOverlay(recordName: record.name)
                        }
                    }
                )
                .statusBarHidden(true)
                .onAppear {
                    if isOverlayVisible { startOverlayAutoHideTimer() }
                }
                .onChange(of: isOverlayVisible) { _, visible in
                    if !visible { overlayAutoHideTimer?.invalidate(); overlayAutoHideTimer = nil }
                    else { startOverlayAutoHideTimer() }
                }
            } else if loadError != nil {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text(loadError ?? "加载失败")
                            .foregroundColor(.secondary)
                        Button("关闭", action: onDismiss)
                    }
                }
            } else {
                CustomZStack {
                    Color(UIColor.systemBackground).ignoresSafeArea()
                    Button("关闭", action: onDismiss)
                }
            }
        }
        .onAppear {
            if let pre = preloadedRecord {
                // 刚制作完成：未保存记录，使用预加载图（仅此路径允许一次性在内存）
                record = pre
                recordIsFromPreload = true
                textSegmentRanges = computeTextSegmentRanges(pre.ocrTextSegments)
                isLoading = false
                if pre.getAudioData() != nil { startPlayback() }
            } else {
                // 已保存记录（首页/历史等）：仅按需加载，不加载全部图片
                recordIsFromPreload = false
                loadRecord()
            }
        }
        .onDisappear {
            stopAudio()
            overlayAutoHideTimer?.invalidate()
            overlayAutoHideTimer = nil
            onDismiss()  // 右进左出：左滑返回时同步清空导航状态
        }
    }
    
    @ViewBuilder
    private func playOverlay(recordName: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            // 播放控制
            HStack(spacing: 24) {
                Button(action: {
                    startOverlayAutoHideTimer()
                    togglePlayback()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: playButtonSize))
                        .foregroundColor(isPlaying ? Color.yellow : Color.green)
                        .frame(width: thumbSize, height: thumbSize)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white, lineWidth: 1)
                                )
                        )
                }
                .disabled(record?.getAudioData() == nil)
                Button(action: {
                    startOverlayAutoHideTimer()
                    stopAndDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: playButtonSize))
                        .foregroundColor(Color.red)
                        .frame(width: thumbSize, height: thumbSize)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white, lineWidth: 1)
                                )
                        )
                }
            }
            .padding(.bottom, isPad ? 48 : 32)
        }
    }
    
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
        } catch {
            os.Logger.audioPlayer.error("❌ PlayView 创建播放器失败: \(error.localizedDescription)")
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
                    currentImageIndex = index
                }
                return
            }
        }
        if progress >= 1.0, !textSegmentRanges.isEmpty {
            currentImageIndex = min(textSegmentRanges.count - 1, record.totalImageCount - 1)
        }
    }
    
    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            playbackTimer?.invalidate()
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            player.play()
            isPlaying = true
            startPlaybackTimer()
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
    
    private func onPlaybackFinished() {
        isPlaying = false
        playbackProgress = 1.0
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer = nil
        audioPlayerDelegate = nil
        UIApplication.shared.isIdleTimerDisabled = false
        PlayHistoryManager.shared.recordPlay(name: record?.name ?? "未命名", playedAt: Date())
        onDismiss()
    }
    
    private func stopAudio() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    private func stopAndDismiss() {
        stopAudio()
        onDismiss()
    }
    
    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    /// 5 秒内无点击、无操作按钮时自动隐藏操作栏
    private func startOverlayAutoHideTimer() {
        overlayAutoHideTimer?.invalidate()
        overlayAutoHideTimer = Timer.scheduledTimer(withTimeInterval: overlayAutoHideInterval, repeats: false) { _ in
            DispatchQueue.main.async {
                isOverlayVisible = false
            }
        }
    }
}

// MARK: - 全屏大图内容
struct FullScreenImageContent<Overlay: View>: View {
    /// 会话 ID，非空时按 index 从 SessionRecordManager 按需加载
    var sessionId: String? = nil
    var totalImageCount: Int = 0
    /// 预加载图（如制作中未保存的会话），非空时优先使用
    var preloadedImages: [UIImage]? = nil
    @Binding var currentIndex: Int
    var onTapBackground: (() -> Void)? = nil
    @ViewBuilder let overlayContent: () -> Overlay
    
    /// 兼容旧用法：直接传入图片数组（如 App 内全屏看图）
    init(images: [UIImage], currentIndex: Binding<Int>, onTapBackground: (() -> Void)? = nil, @ViewBuilder overlayContent: @escaping () -> Overlay) {
        self.sessionId = nil
        self.totalImageCount = images.count
        self.preloadedImages = images
        self._currentIndex = currentIndex
        self.onTapBackground = onTapBackground
        self.overlayContent = overlayContent
    }
    
    init(sessionId: String? = nil, totalImageCount: Int = 0, preloadedImages: [UIImage]? = nil, currentIndex: Binding<Int>, onTapBackground: (() -> Void)? = nil, @ViewBuilder overlayContent: @escaping () -> Overlay) {
        self.sessionId = sessionId
        self.totalImageCount = totalImageCount
        self.preloadedImages = preloadedImages
        self._currentIndex = currentIndex
        self.onTapBackground = onTapBackground
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
                    Color(red: 0.85, green: 0.95, blue: 0.88)
                        .ignoresSafeArea(.all)
                        .onTapGesture { onTapBackground?() }
                    
                    if useOnDemand, let sid = sessionId {
                        // 按需路径：只渲染当前页 + 手势切换，提前预加载相邻图避免闪动
                        GeometryReader { geometry in
                            OnDemandImagePage(sessionId: sid, index: currentIndex, size: geometry.size, onTap: onTapBackground)
                                .id(currentIndex)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 40)
                                        .onEnded { value in
                                            let t = value.translation.width
                                            if t < -40 {
                                                currentIndex = min(currentIndex + 1, imageCount - 1)
                                            } else if t > 40 {
                                                currentIndex = max(0, currentIndex - 1)
                                            }
                                        }
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    }
                    overlayContent()
                }
                .ignoresSafeArea(.all)
            }
        }
        .onTapGesture { onTapBackground?() }
    }
    
    /// 预加载当前页的上一张、下一张，切换时从缓存直接显示、避免闪动
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
                .scaleEffect(1.15)
                .frame(width: size.width, height: size.height)
                .blur(radius: 10)
                .opacity(0.5)
                .clipped()
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(8)
                .onTapGesture { onTapBackground?() }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// 加载单页图
private struct OnDemandImagePage: View {
    let sessionId: String
    let index: Int
    let size: CGSize
    var onTap: (() -> Void)? = nil
    @State private var image: UIImage? = nil
    
    private static let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension
    
    var body: some View {
        CustomZStack(backgroundColor: Color.clear) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(1.15)
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 10)
                    .opacity(0.5)
                    .clipped()
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
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
