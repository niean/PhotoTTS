import SwiftUI
import UIKit
import AVFoundation
import os.log

// MARK: - 制作视图
struct MakeView: View {
    @StateObject private var coordinator = ImageToSpeechCoordinator(
        networkService: NetworkService(),
        settingsManager: SettingsManager.shared
    )
    @ObservedObject var appState: AppState
    
    @State private var capturedImage: UIImage?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isProcessing = false
    @State private var processingProgress: Float = 0.0
    @State private var currentOperation = ""
    @State private var ocrResult = ""
    @State private var audioData: Data?
    @State private var audioResponse: AudioResponse?
    @State private var error: Error?
    @State private var ocrStartTime: Date?
    @State private var ttsStartTime: Date?
    @State private var ocrDuration: TimeInterval = 0.0
    @State private var ttsDuration: TimeInterval = 0.0
    
    // 批量处理相关状态
    @State private var selectedImages: [UIImage] = []
    @State private var currentImageIndex: Int = 0
    @State private var isDragging: Bool = false
    @State private var dragSourceIndex: Int? = nil
    @State private var dragTargetIndex: Int? = nil
    @State private var isProcessingReorder: Bool = false
    
    // 音频播放同步图片：文本分段信息
    @State private var ocrTextSegments: [String] = []  // 每张图片对应的文本段
    @State private var textSegmentRanges: [(start: Int, end: Int)] = []  // 每段文本在总文本中的字符位置范围
    
    // 会话记录相关状态
    @State private var showSaveSessionDialog = false
    @State private var showPhotoPicker = false
    @State private var photoPickerSelectedImages: [UIImage] = []
    @State private var openedCameraFromHome = false   // 从首页发起的拍照，关闭相机时若仍无图则回首页
    @State private var openedPickerFromHome = false  // 从首页发起的选图，取消或未选则回首页
    @State private var isSavingSession = false  // 保存会话记录时的加载状态
    
    // 状态弹出层：失败时持续展示直至用户点击关闭
    @State private var processingOverlayDismissed = false
    /// 制作页 OCR+TTS 完成后用当前数据全屏播放
    @State private var currentSessionToPlay: SessionRecord? = nil
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
        
    var body: some View {
        NavigationStack {
            CustomZStack {
                // 照片处理视图
                photoProcessingView

                // 顶部导航视图
                VStack(spacing: 0) {
                    customNavigationBar
                    Spacer()
                }

            }
            .onChange(of: appState.fullScreenKind) { oldKind, newKind in
                if newKind == nil, oldKind == .camera {
                    let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
                    selectedImages = appState.cameraOverlayImages.map { SessionRecordManager.downsampleImageToMaxPixel($0, maxPixelLength: maxP) ?? $0 }
                    currentImageIndex = max(0, selectedImages.count - 1)
                    onImagesChanged()
                    if openedCameraFromHome {
                        openedCameraFromHome = false
                        if selectedImages.isEmpty {
                            appState.selectedTab = 0
                        }
                    }
                }
            }
            .onChange(of: appState.selectedTab) { _, new in
                if new == 1 {
                    handlePendingFromHome()
                    if let id = appState.sessionIdToLoadIntoMake {
                        appState.sessionIdToLoadIntoMake = nil
                        loadRecordIntoMake(sessionId: id)
                    }
                }
            }
            .onAppear {
                if appState.selectedTab == 1 {
                    handlePendingFromHome()
                    if let id = appState.sessionIdToLoadIntoMake {
                        appState.sessionIdToLoadIntoMake = nil
                        loadRecordIntoMake(sessionId: id)
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { currentSessionToPlay != nil },
                set: { if !$0 { currentSessionToPlay = nil } }
            )) {
                if let record = currentSessionToPlay {
                    PlayView(preloadedRecord: record, onDismiss: { currentSessionToPlay = nil })
                } else {
                    EmptyView()
                }
            }
            .fullScreenCover(isPresented: $showPhotoPicker) {
                MultiImagePicker(
                    selectedImages: $photoPickerSelectedImages,
                    onCompletion: { images in
                        if !images.isEmpty {
                            let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
                            selectedImages = images.map { SessionRecordManager.downsampleImageToMaxPixel($0, maxPixelLength: maxP) ?? $0 }
                            currentImageIndex = 0
                            onImagesChanged()
                        } else if openedPickerFromHome {
                            appState.selectedTab = 0
                        }
                        openedPickerFromHome = false
                        showPhotoPicker = false
                    },
                    onCancel: {
                        if openedPickerFromHome {
                            appState.selectedTab = 0
                        }
                        openedPickerFromHome = false
                        showPhotoPicker = false
                    }
                )
            }
            .navigationDestination(isPresented: $showSaveSessionDialog) {
                let suggestedName: String = {
                    let f = DateFormatter()
                    f.dateFormat = "yy.MM.dd "
                    return f.string(from: Date())
                }()
                SessionRecordUnifiedView(
                    mode: .save(
                        SaveSessionContext(
                            suggestedName: suggestedName,
                            images: selectedImages,
                            textLength: ocrResult.count,
                            imageCount: selectedImages.count
                        ),
                        onSave: { name, avatarIndex in
                            saveCurrentSession(name: name, avatarImageIndex: avatarIndex)
                            showSaveSessionDialog = false
                        },
                        onCancel: {
                            showSaveSessionDialog = false
                        }
                    )
                )
                .onDisappear {
                    showSaveSessionDialog = false
                }
            }
        }
    }

    // 检查是否可以保存会话记录
    private func canSaveSession() -> Bool {
        // 需要有图片、文本和音频数据
        let hasImages = !selectedImages.isEmpty
        let hasText = !ocrResult.isEmpty
        let hasAudio = audioData != nil
        
        return hasImages && hasText && hasAudio
    }
    
    // 格式化存储大小（字节转换为可读格式）
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 用当前页数据构建 SessionRecord（用于未保存会话的 PlayView 全屏播放）
    private func buildCurrentSessionRecord() -> SessionRecord? {
        let images = selectedImages
        guard !images.isEmpty,
              let audioData = audioData,
              let audioResponse = audioResponse else { return nil }
        let audioFormat = audioResponse.format.isEmpty ? "mp3" : audioResponse.format
        return SessionRecord(
            name: "未命名会话",
            images: images,
            ocrText: ocrResult,
            ocrTextSegments: ocrTextSegments,
            audioData: audioData,
            audioFormat: audioFormat,
            audioDuration: audioResponse.duration,
            ocrDuration: ocrDuration,
            ttsDuration: ttsDuration,
            validImageCount: audioResponse.validImageCount ?? images.count,
            voiceSettings: audioResponse.voiceSettings,
            avatarImageIndex: min(max(0, currentImageIndex), images.count > 0 ? images.count - 1 : 0)
        )
    }
    
    // 保存会话记录
    private func saveCurrentSession(name: String, avatarImageIndex: Int = 0) {
        guard canSaveSession() else {
            os.Logger.makeView.error("无法保存会话记录：数据不完整")
            return
        }
        
        let images = selectedImages
        guard !images.isEmpty,
              let audioData = audioData,
              let audioResponse = audioResponse else {
            os.Logger.makeView.error("无法保存会话记录：缺少必要数据")
            return
        }
        
        // 显示保存提示
        isSavingSession = true
        
        // 在后台线程执行保存操作
        DispatchQueue.global(qos: .userInitiated).async {
            // 获取音频格式（从audioResponse或默认mp3）
            let audioFormat = audioResponse.format.isEmpty ? "mp3" : audioResponse.format
            let avatarIndex = min(max(0, avatarImageIndex), images.count > 0 ? images.count - 1 : 0)
            
            // 创建会话记录
            let record = SessionRecord(
                name: name.isEmpty ? "未命名会话" : name,
                images: images,
                ocrText: self.ocrResult,
                ocrTextSegments: self.ocrTextSegments,
                audioData: audioData,
                audioFormat: audioFormat,
                audioDuration: audioResponse.duration,
                ocrDuration: self.ocrDuration,
                ttsDuration: self.ttsDuration,
                validImageCount: audioResponse.validImageCount ?? images.count,
                voiceSettings: audioResponse.voiceSettings,
                avatarImageIndex: avatarIndex
            )
            
            // 保存到文件系统
            let result = SessionRecordManager.shared.saveSession(record)
            
            // 回到主线程更新UI
            DispatchQueue.main.async {
                self.isSavingSession = false
                
                if result.success {
                    MakeHistoryManager.shared.recordSave(name: record.name, savedAt: Date())
                    let sizeText = result.size != nil ? "\n存储空间: \(self.formatStorageSize(result.size!))" : ""
                    os.Logger.makeView.info("会话记录保存成功: \(record.name)\(sizeText)")
                    self.alertMessage = "会话记录已保存\(sizeText)"
                    self.showingAlert = true
                } else {
                    os.Logger.makeView.error("会话记录保存失败")
                    self.alertMessage = "会话记录保存失败"
                    self.showingAlert = true
                }
            }
        }
    }
    
    // 完全清理所有状态
    private func clearAllState() {
        // 清理图片
        capturedImage = nil
        selectedImages.removeAll()
        currentImageIndex = 0
        appState.cameraOverlayImages = []
        
        // 清理文本
        ocrResult = ""
        ocrTextSegments = []
        textSegmentRanges = []
        
        // 清理音频
        audioData = nil
        audioResponse = nil
        
        // 清理处理状态
        error = nil
        isProcessing = false
        processingProgress = 0.0
        currentOperation = ""
        
        // 清理计时器
        ocrDuration = 0.0
        ttsDuration = 0.0
        ocrStartTime = nil
        ttsStartTime = nil
        
        // 清理拖拽状态
        isDragging = false
        dragSourceIndex = nil
        dragTargetIndex = nil
        isProcessingReorder = false
    }
    
    /// 处理从首页跳转过来的待办：拍照、选图
    private func handlePendingFromHome() {
        if appState.openPhotoPickerOnNextRecordAppear {
            appState.openPhotoPickerOnNextRecordAppear = false
            clearAllState()
            openedPickerFromHome = true
            showPhotoPicker = true
            return
        }
        if appState.openCameraOnNextRecordAppear {
            appState.openCameraOnNextRecordAppear = false
            clearAllState()
            openedCameraFromHome = true
            checkCameraPermissionAndTakePhoto()
            return
        }
    }
    
    /// 从记录管理「加载到制作」：按会话 ID 加载图片到制作页，清空 OCR/音频，便于重新识别与合成；按 saveImageMaxPixel 限制加载
    private func loadRecordIntoMake(sessionId: String) {
        guard let record = SessionRecordManager.shared.loadSession(id: sessionId) else { return }
        let count = record.totalImageCount
        guard count > 0 else { return }
        // 按点换算使解码边长不超过 saveImageMaxPixel，避免大图解码
        let scale = max(1, UIScreen.main.scale)
        let maxDim = Constants.ImageDisplay.saveImageMaxPixel / scale
        DispatchQueue.global(qos: .userInitiated).async {
            var images: [UIImage] = []
            for index in 0..<count {
                if let img = SessionRecordManager.shared.loadImage(sessionId: sessionId, index: index, maxDimension: maxDim) {
                    images.append(img)
                }
            }
            DispatchQueue.main.async {
                self.selectedImages = images
                self.currentImageIndex = 0
                self.onImagesChanged()
            }
        }
    }
    
    // MARK: - 照片处理视图
    private var photoProcessingView: some View {
        // 制作与播放视图：照片处理区域
        PhotoProcessingView(
            image: capturedImage,
            selectedImages: selectedImages,
            currentImageIndex: currentImageIndex,
            isProcessing: isProcessing,
            processingProgress: processingProgress,
            currentOperation: currentOperation,
            ocrResult: ocrResult,
            ocrTextSegments: ocrTextSegments,
            audioData: audioData,
            audioResponse: audioResponse,
            error: error,
            showProcessingOverlay: isProcessing || (error != nil && !processingOverlayDismissed),
            onDismissErrorOverlay: { processingOverlayDismissed = true },
            onCancelProcessing: { coordinator.cancelProcessing() },
            isPlaying: false,
            playbackProgress: 0,
            ocrDuration: ocrDuration,
            ttsDuration: ttsDuration,
            allowChangeOperations: true,
            onTogglePlayback: { togglePlayback() },
            onProcessOCRTTS: {
                processingOverlayDismissed = false
                clearDataAndState()
                processImages()
            },
            onTakePhoto: {
                checkCameraPermissionAndTakePhoto()
            },
            onOpenPhotoPicker: {
                showPhotoPicker = true
            },
            onSelectImage: { index in
                selectImage(at: index)
            },
            onRemoveImage: { index in
                removeImageFromBatch(at: index)
            },
            onClearAllImages: {
                clearAllImages()
            },
            onSaveSession: {
                // 检查是否可以保存会话记录
                if canSaveSession() {
                    showSaveSessionDialog = true
                }
            },
            isDragging: $isDragging,
            dragSourceIndex: $dragSourceIndex,
            dragTargetIndex: $dragTargetIndex,
            isProcessingReorder: $isProcessingReorder,
            onReorderImages: { sourceIndex, targetIndex in
                reorderImages(from: sourceIndex, to: targetIndex)
            }
        )
        .navigationBarHidden(true)
        .alert("提示", isPresented: $showingAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .overlay {
            // 保存会话记录时的加载提示
            if isSavingSession {
                CustomZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("正在保存会话记录")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
        }
        .onChange(of: capturedImage) { _, newImage in
            if let newImage = newImage {
                let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
                let capped = SessionRecordManager.downsampleImageToMaxPixel(newImage, maxPixelLength: maxP) ?? newImage
                selectedImages.append(capped)
                onImagesChanged()
                currentImageIndex = selectedImages.count - 1
                capturedImage = nil
            }
        }
        .onChange(of: error?.localizedDescription) { _, description in
                if let description = description {
                    alertMessage = "处理失败: \(description)"
            }
        }
    }
    
    private var recordPageNavigationTitle: String { "制作" }
    
    // MARK: - 顶部导航视图
    private var customNavigationBar: some View {
        CustomNavigationBar(title: recordPageNavigationTitle, trailing: {
            Menu {
                Button { checkCameraPermissionAndTakePhoto() } label: {
                    Label("拍照", systemImage: "camera.fill")
                }
                .disabled(isProcessing)
                Divider()
                Button { if canSaveSession() { showSaveSessionDialog = true } } label: {
                    Label("保存", systemImage: "bookmark.fill")
                }
                .disabled(!canSaveSession())
                Divider()
                Button { clearAllState() } label: {
                    Label("清空", systemImage: "trash.fill")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: isPad ? 24 : 22))
                    .foregroundColor(.blue)
                    .background(Color.clear)
            }
        })
    }

    // 数据和状态清理(不包括图片)
    private func clearDataAndState() {
        // 数据清理
        ocrResult = ""
        audioData = nil

        // 状态清理
        error = nil
        isProcessing = false
        processingProgress = 0.0
        currentOperation = ""
        ocrDuration = 0.0 
        ttsDuration = 0.0
        ocrStartTime = nil
        ttsStartTime = nil
    }

    /// 图片列表发生变化时调用，清空 OCR/音频等衍生状态（增删改顺序都会触发）
    private func onImagesChanged() {
        clearDataAndState()
    }

    /// 播放：用 PlayView 全屏播放当前制作数据
    private func togglePlayback() {
        guard audioData != nil else {
            os.Logger.audioPlayer.error("❌ 没有音频数据，请先完成OCR和TTS处理")
            return
        }
        if let record = buildCurrentSessionRecord() {
            currentSessionToPlay = record
        }
    }
    
    // 解析OCR结果，保存文本分段信息用于音频播放同步
    private func parseOCRTextSegments(_ combinedText: String) {
        let separator = Constants.ocrTextSeparator
        let segments = combinedText.components(separatedBy: separator)
        
        // 保留所有段（包括空段），以保持与图片索引的对应关系
        // 这样即使OCR失败或图片为空，也能正确同步图片和音频
        ocrTextSegments = segments
        
        // 如果没有分段，说明只有一张图片或没有分隔符
        if ocrTextSegments.isEmpty && !combinedText.isEmpty {
            ocrTextSegments = [combinedText]
        }
        
        // 计算每段文本在总文本中的字符位置范围
        textSegmentRanges = []
        var currentPosition = 0
        
        for (index, segment) in ocrTextSegments.enumerated() {
            let start = currentPosition
            let segmentLength = segment.count
            let end = currentPosition + segmentLength
            
            textSegmentRanges.append((start: start, end: end))
            
            // 更新位置，加上分隔符长度（除了最后一段）
            currentPosition = end
            if index < ocrTextSegments.count - 1 {
                currentPosition += separator.count
            }
        }
        
        // 确保最后一段的范围延伸到文本末尾（处理可能的边界情况）
        if !textSegmentRanges.isEmpty && !combinedText.isEmpty {
            let lastIndex = textSegmentRanges.count - 1
            let lastRange = textSegmentRanges[lastIndex]
            textSegmentRanges[lastIndex] = (start: lastRange.start, end: combinedText.count)
        }
        
        // 统计空段数量
        let emptySegmentsCount = ocrTextSegments.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        os.Logger.makeView.debug("文本分段解析完成: \(ocrTextSegments.count) 段（空段: \(emptySegmentsCount)），总长度: \(combinedText.count)")
        for (index, range) in textSegmentRanges.enumerated() {
            let segmentText = ocrTextSegments[index]
            let isEmpty = segmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            os.Logger.makeView.debug("   段 \(index): 位置 \(range.start)-\(range.end)，长度: \(range.end - range.start)\(isEmpty ? " (空)" : "")")
        }
    }
    
    // MARK: - 统一处理函数
    
    // 统一的图片处理函数（批量模式）
    private func processImages() {
        guard !selectedImages.isEmpty else { return }

        var imageDataList: [Data] = []
        for image in selectedImages {
            if let data = image.jpegData(compressionQuality: 0.8) {
                imageDataList.append(data)
            }
        }
        
        guard !imageDataList.isEmpty else {
            error = NSError(domain: "PhotoTTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法转换图片数据"])
            return
        }
        
        processImagesWithData(imageDataList)
    }
    
    // 统一的数据处理函数
    private func processImagesWithData(_ imageDataList: [Data]) {
        isProcessing = true
        processingProgress = 0.0
        currentOperation = "开始处理图片..."
        error = nil
        ocrResult = ""
        audioData = nil
        
        // 重置计时器
        ocrDuration = 0.0
        ttsDuration = 0.0
        ocrStartTime = Date()
        ttsStartTime = nil
        
        // 进度处理函数
        let progressHandler: (ProcessingProgress) -> Void = { [self] progress in
            DispatchQueue.main.async {
                // 统一的进度转换逻辑
                let normalizedProgress = max(0.0, min(1.0, progress.percentage / 100.0))
                self.processingProgress = Float(normalizedProgress)
                self.currentOperation = progress.message
                
                // 记录TTS开始时间
                if progress.message.contains("TTS") && self.ttsStartTime == nil {
                    self.ttsStartTime = Date()
                    os.Logger.makeView.debug("TTS开始时间: \(self.ttsStartTime!)")
                }
                
                // 计算OCR耗时
                if progress.message.contains("OCR") && self.ocrStartTime != nil {
                    let currentTime = Date()
                    self.ocrDuration = currentTime.timeIntervalSince(self.ocrStartTime!)
                    os.Logger.makeView.debug("OCR已耗时: \(String(format: "%.2f", self.ocrDuration))秒")
                }
                
                // 计算TTS耗时
                if progress.message.contains("TTS") && self.ttsStartTime != nil {
                    let currentTime = Date()
                    self.ttsDuration = currentTime.timeIntervalSince(self.ttsStartTime!)
                    os.Logger.makeView.debug("TTS已耗时: \(String(format: "%.2f", self.ttsDuration))秒")
                }
            }
        }
        
        // 完成处理函数
        let completionHandler: (Result<AudioResponse, ImageToSpeechProcessingError>) -> Void = { [self] result in
            DispatchQueue.main.async {
                self.isProcessing = false
                
                // 计算最终耗时
                let endTime = Date()
                if let ocrStart = self.ocrStartTime {
                    self.ocrDuration = endTime.timeIntervalSince(ocrStart)
                }
                if let ttsStart = self.ttsStartTime {
                    self.ttsDuration = endTime.timeIntervalSince(ttsStart)
                }
                
                switch result {
                case .success(let audioResponse):
                    self.ocrResult = audioResponse.text
                    self.audioData = audioResponse.audioData
                    self.audioResponse = audioResponse
                    self.processingProgress = 1.0
                    self.currentOperation = "处理完成"
                    
                    // 解析OCR文本分段，用于音频播放同步和展示
                    if !audioResponse.text.isEmpty {
                        self.parseOCRTextSegments(audioResponse.text)
                    }
                    
                    // 统一的完成日志
                    let totalDuration = self.ocrDuration + self.ttsDuration
                    os.Logger.makeView.info("处理完成!")
                    os.Logger.makeView.info("OCR耗时: \(String(format: "%.2f", self.ocrDuration))秒")
                    os.Logger.makeView.info("TTS耗时: \(String(format: "%.2f", self.ttsDuration))秒")
                    os.Logger.makeView.info("总耗时: \(String(format: "%.2f", totalDuration))秒")
                    os.Logger.makeView.info("文字长度: \(audioResponse.text.count)字符")
                    os.Logger.makeView.info("音频大小: \(ByteCountFormatter.string(fromByteCount: Int64(audioResponse.audioData?.count ?? 0), countStyle: .file))")
                    
                    // 自动播放语音（有音频时）
                    if audioResponse.audioData != nil {
                        os.Logger.makeView.debug("开始自动播放")
                        self.togglePlayback()
                    } else {
                        os.Logger.makeView.warning("没有音频数据，无法播放")
                    }
                    
                case .failure(let processingError):
                    self.error = processingError
                    self.processingProgress = 0.0
                    self.currentOperation = "处理失败"
                    os.Logger.makeView.error("处理失败: \(processingError.localizedDescription)")
                }
            }
        }
        
        // 批量处理函数
        coordinator.convertBatchImagesToSpeech(imageDataList, progressHandler: progressHandler, completion: completionHandler)
    }

    // MARK: - 批量处理相关函数
    
    // 从批量队列中删除图片
    private func removeImageFromBatch(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        onImagesChanged()
        if selectedImages.isEmpty {
            currentImageIndex = 0
        } else if currentImageIndex >= selectedImages.count {
            currentImageIndex = selectedImages.count - 1
        }
    }
    
    // 选择批量队列中的图片
    private func selectImage(at index: Int) {
        guard index < selectedImages.count else { return }
        currentImageIndex = index
    }
    
    // 清空所有图片
    private func clearAllImages() {
        selectedImages.removeAll()
        onImagesChanged()
        currentImageIndex = 0
    }
    
    // 重新排序图片
    private func reorderImages(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex < selectedImages.count,
              targetIndex < selectedImages.count else { return }
        selectedImages.swapAt(sourceIndex, targetIndex)
        onImagesChanged()
        if currentImageIndex == sourceIndex {
            currentImageIndex = targetIndex
        } else if currentImageIndex == targetIndex {
            currentImageIndex = sourceIndex
        }
    }
    
    // 检查相机权限并拍照
    private func checkCameraPermissionAndTakePhoto() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            appState.cameraOverlayImages = selectedImages
            appState.fullScreenKind = .camera
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.appState.cameraOverlayImages = self.selectedImages
                        self.appState.fullScreenKind = .camera
                    } else {
                        alertMessage = "需要相机权限才能拍照"
                        showingAlert = true
                    }
                }
            }
        case .denied, .restricted:
            alertMessage = "请在设置中允许访问相机"
            showingAlert = true
        @unknown default:
            alertMessage = "相机权限未知状态"
            showingAlert = true
        }
    }
    
}

// MARK: - 照片处理视图
struct PhotoProcessingView: View {
    let image: UIImage?
    let selectedImages: [UIImage]
    let currentImageIndex: Int
    let isProcessing: Bool
    let processingProgress: Float
    let currentOperation: String
    let ocrResult: String
    let ocrTextSegments: [String]  // OCR文本分段，用于展示
    let audioData: Data?
    let audioResponse: AudioResponse?
    let error: Error?
    let showProcessingOverlay: Bool
    let onDismissErrorOverlay: () -> Void
    let onCancelProcessing: () -> Void
    let isPlaying: Bool
    let playbackProgress: Double
    let ocrDuration: TimeInterval
    let ttsDuration: TimeInterval
    /// 是否允许变更操作（识别、删除、保存、拍照、缩略图顺序/删除）
    let allowChangeOperations: Bool
    let onTogglePlayback: () -> Void
    let onProcessOCRTTS: () -> Void
    let onTakePhoto: () -> Void
    let onOpenPhotoPicker: () -> Void  // 选图制作（与首页入口一致）
    let onSelectImage: (Int) -> Void
    let onRemoveImage: (Int) -> Void
    let onClearAllImages: () -> Void
    let onSaveSession: () -> Void  // 保存会话记录回调
    @Binding var isDragging: Bool
    @Binding var dragSourceIndex: Int?
    @Binding var dragTargetIndex: Int?
    @Binding var isProcessingReorder: Bool
    let onReorderImages: (Int, Int) -> Void
    
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    
    private struct LayoutMetrics {
        let defaultMargin: CGFloat = Constants.Layout.defaultMargin
        let screenWidth: CGFloat
        let contentWidth: CGFloat
        let deltaScreenContentWidth: CGFloat
        let imageAreaHeight: CGFloat
        let thumbSize: CGFloat
        let thumbMargin: CGFloat
        let thumbBarHeight: CGFloat
        let imageAreaTotalHeight: CGFloat
        let buttomTabHeight: CGFloat
        init(geometry: GeometryProxy, isPad: Bool) {
            screenWidth = geometry.size.width
            deltaScreenContentWidth = 16
            contentWidth = screenWidth - deltaScreenContentWidth
            thumbSize = isPad ? 60 : 55
            thumbMargin = 5
            thumbBarHeight = thumbSize + thumbMargin * 2
            buttomTabHeight = isPad ? 0 : 0
            let spacingTotal: CGFloat = 40
            imageAreaHeight = max(200, geometry.size.height - buttomTabHeight - thumbBarHeight - spacingTotal)
            imageAreaTotalHeight = imageAreaHeight + thumbBarHeight + spacingTotal
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let layout = LayoutMetrics(geometry: geometry, isPad: isPad)
            VStack(spacing: 0) {
                CustomZStack(alignment: .bottom) {
                    // 图片预览
                    imagePreviewSection(layout: layout)

                    // 状态展示（图片预览之上的弹出层）
                    if showProcessingOverlay {
                        processingSection(
                            layout: layout,
                            onDismissErrorOverlay: onDismissErrorOverlay,
                            onCancelProcessing: onCancelProcessing
                        )
                    }
                }

                Spacer()
            }
            .frame(maxWidth: layout.screenWidth)
            .padding(.top, Constants.Layout.topNavigationBarPadding)
        }
    }
    
    // MARK: - 图片预览
    @ViewBuilder
    private func imagePreviewSection(layout: LayoutMetrics) -> some View {
        VStack(spacing: 2) {
            if selectedImages.isEmpty {
                // 首页操作入口
                VStack(spacing: 24) {
                    Spacer()
                    Spacer()
                    // 拍照制作
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: isPad ? 100 : 80))
                            .foregroundColor(.blue)
                        Text("拍照制作")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTakePhoto()
                    }
                    .disabled(isProcessing || isPlaying || !allowChangeOperations)

                    Spacer()
                    // 选图制作
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: isPad ? 100 : 80))
                            .foregroundColor(.blue)
                        Text("选图制作")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpenPhotoPicker()
                    }
                    .disabled(!allowChangeOperations)
                    Spacer()
                    Spacer()
                }
            } else {
                // !selectedImages.isEmpty
                // 大图(当前图片)
                VStack {
                    TabView(selection: Binding(
                        get: { currentImageIndex },
                        set: { newIndex in
                            if newIndex != currentImageIndex {
                                onSelectImage(newIndex)
                            }
                        }
                    )) {
                        ForEach(0..<selectedImages.count, id: \.self) { index in
                            Image(uiImage: selectedImages[index])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(8)
                                .tag(index)
                                .onTapGesture {
                                }
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .padding(.horizontal, layout.defaultMargin/2)
                    .padding(.top, layout.defaultMargin/2)
                }
                .frame(maxWidth: layout.contentWidth, maxHeight: layout.imageAreaHeight)

                // 
                HStack(spacing: 5) {
                    // 识别按钮
                    Button(action: {
                        onProcessOCRTTS()
                    }) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: isPad ? 28 : 25, weight: .semibold))
                            .foregroundColor(isProcessing || selectedImages.isEmpty ? Color.gray : Color.green)
                            .frame(width: layout.thumbSize, height: layout.thumbSize)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(isProcessing || selectedImages.isEmpty || !allowChangeOperations)
                    .padding(.leading, 6)

                    // 播放按钮
                    Button(action: {
                        onTogglePlayback()
                    }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isPad ? 28 : 25))
                            .foregroundColor(
                                isProcessing || audioData == nil ? Color.gray :
                                (isPlaying ? Color.yellow : Color.green)
                            )
                            .frame(width: layout.thumbSize, height: layout.thumbSize)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(isProcessing || audioData == nil)
                    .padding(.leading, 6)

                    // 缩略图列表
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(0..<selectedImages.count, id: \.self) { index in
                                    CustomZStack(backgroundColor: Color.clear) {
                                        Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: layout.thumbSize, height: layout.thumbSize)
                                        .cornerRadius(8)
                                        .clipped()
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(currentImageIndex == index ? Color.blue : Color.clear, 
                                                        lineWidth: currentImageIndex == index ? min(2, layout.thumbMargin*0.5) : 0)
                                        )
                                        .onTapGesture {
                                            onSelectImage(index)
                                        }
                                        .onLongPressGesture(minimumDuration: 0.5) {
                                            os.Logger.makeView.debug("onLongPress: 长按缩略图 \(index)")
                                        } onPressingChanged: { pressing in
                                        }
                                        .onDrag {
                                            if !allowChangeOperations || isProcessingReorder {
                                                return NSItemProvider(object: "" as NSString)
                                            }
                                            dragSourceIndex = index
                                            isDragging = true
                                            os.Logger.makeView.debug("onDrag: 开始拖拽 \(index)")
                                            return NSItemProvider(object: "\(index)" as NSString)
                                        }
                                        .onDrop(of: [.text], isTargeted: nil) { providers in
                                            if !allowChangeOperations || isProcessingReorder {
                                                return false
                                            }
                                            guard let provider = providers.first else { return false }
                                            
                                            DispatchQueue.global(qos: .userInitiated).async {
                                                provider.loadItem(forTypeIdentifier: "public.text", options: nil) { (item, error) in
                                                    if let data = item as? Data,
                                                    let sourceIndexString = String(data: data, encoding: .utf8),
                                                    let sourceIndex = Int(sourceIndexString) {
                                                        
                                                        DispatchQueue.main.async {
                                                            isProcessingReorder = true
                                                            os.Logger.makeView.debug("onDrop: 开始重排序")
                                                            
                                                            dragTargetIndex = index
                                                            if sourceIndex != index {
                                                                onReorderImages(sourceIndex, index)
                                                                os.Logger.makeView.debug("onDrop: 执行排序从 \(sourceIndex) 到 \(index)")
                                                            }
                                                            
                                                            // 延迟重置拖拽状态，确保UI稳定
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                                dragSourceIndex = nil
                                                                dragTargetIndex = nil
                                                                isDragging = false
                                                                isProcessingReorder = false
                                                                os.Logger.makeView.debug("onDrop: 重排序处理完成，重新启用拖拽")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            return true
                                        }
                                    
                                        // 删除按钮
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Button(action: {
                                                    onRemoveImage(index)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .opacity(allowChangeOperations ? 0.5 : 0)
                                                }
                                                .padding(2)
                                                .disabled(!allowChangeOperations)
                                                .allowsHitTesting(allowChangeOperations)
                                            }
                                            Spacer()
                                        }
                                        .frame(width: layout.thumbSize, height: layout.thumbSize)
                                        
                                        // 图片索引号
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Text("\(index + 1)")
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                            }
                                        }
                                        .frame(width: layout.thumbSize, height: layout.thumbSize)
                                    }
                                    .id(index)
                                }
                                Spacer()
                            }
                            .frame(height: layout.thumbBarHeight)
                            .padding(.leading, 6)
                        }
                        .onChange(of: currentImageIndex) { _, newIndex in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: layout.contentWidth, maxHeight: layout.imageAreaTotalHeight)
        .background(
                RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
            )
    }
    
    // MARK: - 状态展示
    @ViewBuilder
    private func processingSection(
        layout: LayoutMetrics,
        onDismissErrorOverlay: (() -> Void)? = nil,
        onCancelProcessing: (() -> Void)? = nil
    ) -> some View {
        CustomZStack(backgroundColor: Color.clear) {
            VStack() {
                Spacer()
                if isProcessing {
                    ProcessingStatusView(
                        processingProgress: processingProgress,
                        currentOperation: currentOperation
                    )
                } else if let err = error {
                    ErrorView(error: err)
                } else if !ocrResult.isEmpty {
                    ProcessingResultView(
                        ocrTextSegments: ocrTextSegments,
                        selectedImages: selectedImages,
                        currentImageIndex: currentImageIndex,
                        isPlaying: isPlaying,
                        audioData: audioData,
                        ocrDuration: ocrDuration,
                        ttsDuration: ttsDuration,
                        validImageCount: audioResponse?.validImageCount
                    )
                }
            }

            // 取消+关闭：if (isProcessing && onCancelProcessing != nil) || (error != nil && onDismissErrorOverlay != nil) {
            if error != nil {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            if isProcessing {
                                // 取消
                                onCancelProcessing?()
                            } else {
                                // 关闭：出错了，关闭弹层
                                onDismissErrorOverlay?()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                                .contentShape(Rectangle())
                        }
                        .padding(12)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: layout.contentWidth, maxHeight: layout.imageAreaTotalHeight)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
        .allowsHitTesting(true)
        .clipped()
    }
    
}

// MARK: - 处理状态视图
struct ProcessingStatusView: View {
    let processingProgress: Float
    let currentOperation: String
    
    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(200, geometry.size.width - 16)
            VStack(spacing: 16) {
                ProgressView(value: processingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(maxWidth: contentWidth - 68)
                
                Text(currentOperation)
                    .font(.headline)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text("\(Int(processingProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding()
        }
    }
}

// MARK: - 处理结果视图
struct ProcessingResultView: View {
    let ocrTextSegments: [String]  // OCR文本分段
    let selectedImages: [UIImage]
    let currentImageIndex: Int  // 当前图片索引，用于滚动同步
    let isPlaying: Bool  // 是否正在播放，用于控制自动滚动
    let audioData: Data?
    let ocrDuration: TimeInterval
    let ttsDuration: TimeInterval
    let validImageCount: Int?
    
    private var totalTextLength: Int {
        return ocrTextSegments.reduce(0) { $0 + $1.count }
    }
    
    // 计算正确图片数量（非空、非失败）
    private var correctImageCount: Int {
        return ocrTextSegments.filter { segment in
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != AppConstants.ocrEmptyResultIndicator
        }.count
    }
    
    var body: some View {
        // 打印OCR识别结果日志
        let _ = os.Logger.makeView.debug("[ProcessingResultView] OCR文本分段数: \(ocrTextSegments.count)")
        let _ = os.Logger.makeView.debug("[ProcessingResultView] OCR结果总长度: \(totalTextLength) 字符")
        let _ = os.Logger.makeView.debug("[ProcessingResultView] 音频数据状态: \(audioData != nil ? "有音频" : "无音频")")
        
        GeometryReader { _ in
            // 区域2. 处理状态-文本展示
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(0..<ocrTextSegments.count, id: \.self) { index in
                                Text("[图片\(index + 1)]：\(ocrTextSegments[index])")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("segment_\(index)")  // 标记ID，用于滚动定位
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .onChange(of: currentImageIndex) { oldValue, newIndex in
                        // 当图片索引变化时，自动滚动到对应的文本段
                        if newIndex >= 0 && newIndex < ocrTextSegments.count {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("segment_\(newIndex)", anchor: .top)
                            }
                            os.Logger.makeView.debug("文字滚动同步: 滚动到图片 \(newIndex + 1) 的文本段")
                        }
                    }
                }
                    
                HStack {
                    Spacer()
                    Text("OCR:\(String(format: "%.0f", ocrDuration))s, TTS:\(String(format: "%.0f", ttsDuration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.all, 3)
                        .cornerRadius(5)
                    
                    Text("图片:\(correctImageCount)/\(selectedImages.count)张, 文本:\(totalTextLength)B, 音频:\(ByteCountFormatter.string(fromByteCount: Int64(audioData?.count ?? 0), countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.all, 3)
                        .cornerRadius(5)
                        .padding(.trailing, 10)
                }
                .frame(height: 12)
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding()
        }
    }
}

// MARK: - 错误视图
struct ErrorView: View {
    let error: Error
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("处理失败")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3) // 限制行数，防止过高
        }
        .padding()
    }
}

// MARK: - 音频播放器代理
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onPlaybackFinished: () -> Void
    
    init(onPlaybackFinished: @escaping () -> Void) {
        self.onPlaybackFinished = onPlaybackFinished
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onPlaybackFinished()
    }
}