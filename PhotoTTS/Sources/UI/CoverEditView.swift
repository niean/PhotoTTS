import SwiftUI
import UIKit
import os.log

// MARK: - 图片编辑模式
enum ImageEditMode {
    case cover   // 16:9, image_0, saves cover.jpg
    case avatar  // 1:1, image_{index}, saves avatar.jpg
}

// MARK: - 图片裁剪编辑弹窗
struct CoverEditView: View {
    let sessionId: String
    let editMode: ImageEditMode
    let imageIndex: Int
    let onDismiss: () -> Void

    init(sessionId: String, editMode: ImageEditMode = .cover, imageIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.sessionId = sessionId
        self.editMode = editMode
        self.imageIndex = imageIndex
        self.onDismiss = onDismiss
    }

    @State private var rotation: Int = 0  // 0, 90, 180, 270
    @State private var originalImage: UIImage?
    @State private var rotatedImage: UIImage?
    @State private var imageOffset: CGSize = .zero
    @State private var imageScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var previewContainerSize: CGSize = .zero
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let coverManager = CoverImageManager()

    private static let logger = os.Logger.coverEdit

    private var aspectRatio: CGFloat {
        switch editMode {
        case .cover: return Constants.HomeCard.coverAspectRatio
        case .avatar: return 1.0
        }
    }

    private var navigationTitle: String {
        switch editMode {
        case .cover: return "编辑封面"
        case .avatar: return "编辑头像"
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else if let image = rotatedImage {
                    VStack(spacing: 20) {
                        // 图片展示区
                        imagePreviewSection(image: image)

                        // 控制按钮
                        controlButtonsSection

                        // 底部操作按钮
                        bottomButtonsSection
                    }
                    .padding()
                } else {
                    Text("无法加载图片")
                        .foregroundColor(.white)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadOriginalImage()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    // MARK: - 图片预览区

    @ViewBuilder
    private func imagePreviewSection(image: UIImage) -> some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height
            let imageAspect = image.size.width / image.size.height

            // 计算显示尺寸（未缩放）
            let displaySize = calculateDisplaySize(
                imageAspect: imageAspect,
                containerWidth: containerWidth,
                containerHeight: containerHeight
            )
            let displayWidth = displaySize.width
            let displayHeight = displaySize.height

            // 裁剪框尺寸（基于原始显示区域，不受缩放影响）
            let cropDims = calculateCropSize(
                width: displayWidth, height: displayHeight, aspectRatio: aspectRatio
            )
            let cropWidth = cropDims.width
            let cropHeight = cropDims.height

            // 合并缩放（钳制范围 1.0~3.0）
            let combinedScale = clampValue(imageScale * pinchScale, min: 1.0, max: 3.0)

            // 缩放后的图片显示尺寸
            let scaledDisplayWidth = displayWidth * combinedScale
            let scaledDisplayHeight = displayHeight * combinedScale

            // 最大偏移量（保证裁剪框不超出缩放后的图片范围）
            let maxOffsetX = max((scaledDisplayWidth - cropWidth) / 2, 0)
            let maxOffsetY = max((scaledDisplayHeight - cropHeight) / 2, 0)

            // 合并并钳制偏移量
            let combinedOffset = CGSize(
                width: clampValue(imageOffset.width + dragOffset.width, min: -maxOffsetX, max: maxOffsetX),
                height: clampValue(imageOffset.height + dragOffset.height, min: -maxOffsetY, max: maxOffsetY)
            )

            // 手势识别
            let dragGesture = DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let cs = clampValue(imageScale, min: 1.0, max: 3.0)
                    let mox = max((displayWidth * cs - cropWidth) / 2, 0)
                    let moy = max((displayHeight * cs - cropHeight) / 2, 0)
                    imageOffset = CGSize(
                        width: clampValue(imageOffset.width + value.translation.width, min: -mox, max: mox),
                        height: clampValue(imageOffset.height + value.translation.height, min: -moy, max: moy)
                    )
                }

            let magnifyGesture = MagnificationGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    let newScale = clampValue(imageScale * value, min: 1.0, max: 3.0)
                    imageScale = newScale
                    // 缩放变化后重新钳制偏移量
                    let mox = max((displayWidth * newScale - cropWidth) / 2, 0)
                    let moy = max((displayHeight * newScale - cropHeight) / 2, 0)
                    imageOffset = CGSize(
                        width: clampValue(imageOffset.width, min: -mox, max: mox),
                        height: clampValue(imageOffset.height, min: -moy, max: moy)
                    )
                }

            ZStack {
                // 原图（可拖动+缩放）
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayWidth, height: displayHeight)
                    .scaleEffect(combinedScale)
                    .offset(combinedOffset)

                // 裁剪框覆盖层（固定居中）
                CropOverlayView(cropWidth: cropWidth, cropHeight: cropHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .gesture(dragGesture.simultaneously(with: magnifyGesture))
            .onAppear {
                previewContainerSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                previewContainerSize = newSize
            }
        }
    }

    // MARK: - 控制按钮区

    private var controlButtonsSection: some View {
        HStack(spacing: 40) {
            // 旋转按钮（逆时针）
            Button(action: rotateImage) {
                VStack(spacing: 8) {
                    Image(systemName: "rotate.left")
                        .font(Constants.Fonts.coverEditIcon)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                    Text("旋转")
                        .font(Constants.Fonts.caption)
                        .foregroundColor(.white)
                }
            }

            // 重置按钮
            Button(action: resetImage) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(Constants.Fonts.coverEditIcon)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                    Text("重置")
                        .font(Constants.Fonts.caption)
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - 底部操作按钮

    private var bottomButtonsSection: some View {
        HStack(spacing: 20) {
            Button(action: {
                onDismiss()
            }) {
                Text("取消")
                    .font(Constants.Fonts.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.gray.opacity(0.5))
                    .cornerRadius(12)
            }

            Button(action: saveImage) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("确认")
                            .font(Constants.Fonts.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isSaving)
        }
    }

    // MARK: - 私有方法

    /// 钳制数值到指定范围
    private func clampValue(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }

    /// 计算图片在容器中的显示尺寸
    private func calculateDisplaySize(imageAspect: CGFloat, containerWidth: CGFloat, containerHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let containerAspect = containerWidth / containerHeight
        if imageAspect > containerAspect {
            return (containerWidth, containerWidth / imageAspect)
        } else {
            return (containerHeight * imageAspect, containerHeight)
        }
    }

    /// 计算裁剪框尺寸
    private func calculateCropSize(width: CGFloat, height: CGFloat, aspectRatio: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let imgAspect = width / height
        if imgAspect > aspectRatio {
            return (height * aspectRatio, height)
        } else {
            return (width, width / aspectRatio)
        }
    }

    private func loadOriginalImage() {
        let idx = imageIndex
        DispatchQueue.global(qos: .userInitiated).async {
            // 按 imageIndex 加载指定图片
            let sessionDir = SessionRecordManager.shared.sessionsDirectory
                .appendingPathComponent(sessionId, isDirectory: true)
            let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
            let imageURL = imagesDir.appendingPathComponent("image_\(idx).jpg")

            guard FileManager.default.fileExists(atPath: imageURL.path),
                  let imageData = try? Data(contentsOf: imageURL),
                  let image = UIImage(data: imageData) else {
                Self.logger.error("图片加载失败: image_\(idx).jpg, session=\(sessionId)")
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "无法加载图片"
                    showError = true
                }
                return
            }

            DispatchQueue.main.async {
                originalImage = image
                rotatedImage = image
                isLoading = false
            }
        }
    }

    private func rotateImage() {
        // 逆时针旋转 90 度（CIImage 坐标系中正角度 = 逆时针）
        rotation = (rotation + 90) % 360
        imageOffset = .zero
        imageScale = 1.0
        applyRotation()
    }

    private func resetImage() {
        rotation = 0
        imageOffset = .zero
        imageScale = 1.0
        rotatedImage = originalImage
    }

    /// 仅旋转，不裁剪（裁剪在保存时根据偏移量计算）
    private func applyRotation() {
        guard let original = originalImage else { return }

        if rotation == 0 {
            rotatedImage = original
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard var ci = CIImage(image: original) else {
                DispatchQueue.main.async {
                    rotatedImage = original
                }
                return
            }

            // 应用旋转
            let radians = CGFloat(rotation) * .pi / 180
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: radians))

            // 处理边界（平移到原点）
            let extent = ci.extent
            ci = ci.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))

            // 转换为 UIImage
            let context = CIContext()
            guard let cgImage = context.createCGImage(ci, from: ci.extent) else {
                DispatchQueue.main.async {
                    rotatedImage = original
                }
                return
            }

            let resultImage = UIImage(cgImage: cgImage)

            DispatchQueue.main.async {
                rotatedImage = resultImage
            }
        }
    }

    private func saveImage() {
        guard let image = rotatedImage,
              previewContainerSize.width > 0 else {
            errorMessage = "图片处理失败"
            showError = true
            return
        }

        isSaving = true

        let capturedOffset = imageOffset
        let capturedScale = imageScale
        let capturedContainerSize = previewContainerSize
        let capturedAspectRatio = aspectRatio
        let capturedEditMode = editMode

        Task {
            do {
                guard let ciImage = CIImage(image: image) else {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = "图片处理失败"
                        showError = true
                    }
                    return
                }

                let imgW = ciImage.extent.width
                let imgH = ciImage.extent.height
                let imageAspect = imgW / imgH

                // 重新计算显示尺寸（与视图中逻辑一致）
                let displaySize = calculateDisplaySize(
                    imageAspect: imageAspect,
                    containerWidth: capturedContainerSize.width,
                    containerHeight: capturedContainerSize.height
                )
                let displayWidth = displaySize.width
                let displayHeight = displaySize.height

                // 裁剪框在显示坐标中的尺寸
                let cropDisplay = calculateCropSize(
                    width: displayWidth, height: displayHeight, aspectRatio: capturedAspectRatio
                )

                // 显示坐标到图片坐标的缩放比（考虑用户缩放）
                let effectiveScale = imgW / (displayWidth * capturedScale)

                // 裁剪区域尺寸（图片坐标）
                let cropImgW = cropDisplay.width * effectiveScale
                let cropImgH = cropDisplay.height * effectiveScale

                // 偏移量映射到图片坐标
                let imgOffsetX = -capturedOffset.width * effectiveScale
                let imgOffsetY = capturedOffset.height * effectiveScale

                let cropX = (imgW - cropImgW) / 2 + imgOffsetX
                let cropY = (imgH - cropImgH) / 2 + imgOffsetY
                let cropRect = CGRect(x: cropX, y: cropY, width: cropImgW, height: cropImgH)

                var cropped = ciImage.cropped(to: cropRect)

                // 平移到原点
                let croppedExtent = cropped.extent
                cropped = cropped.transformed(by: CGAffineTransform(
                    translationX: -croppedExtent.origin.x,
                    y: -croppedExtent.origin.y
                ))

                // 缩放到最大边限制
                let maxDim: CGFloat
                let jpegQuality: CGFloat
                switch capturedEditMode {
                case .cover:
                    maxDim = Constants.HomeCard.coverMaxDimension
                    jpegQuality = Constants.HomeCard.coverJPEGQuality
                case .avatar:
                    maxDim = Constants.ImageDisplay.recordAvatarMaxDimension
                    jpegQuality = 0.85
                }

                let maxSide = max(cropped.extent.width, cropped.extent.height)
                if maxSide > maxDim {
                    let resizeScale = maxDim / maxSide
                    cropped = cropped.transformed(by: CGAffineTransform(scaleX: resizeScale, y: resizeScale))
                }

                // 转换为 JPEG
                let context = CIContext()
                guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = "图片处理失败"
                        showError = true
                    }
                    return
                }

                let resultImage = UIImage(cgImage: cgImage)
                guard let jpegData = resultImage.jpegData(compressionQuality: jpegQuality) else {
                    await MainActor.run {
                        isSaving = false
                        errorMessage = "图片处理失败"
                        showError = true
                    }
                    return
                }

                // 根据编辑模式保存
                switch capturedEditMode {
                case .cover:
                    try saveCoverImage(jpegData: jpegData)
                case .avatar:
                    try saveAvatarImage(jpegData: jpegData)
                }

                await MainActor.run {
                    isSaving = false
                    onDismiss()
                }
            } catch {
                Self.logger.error("保存失败: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    errorMessage = "保存失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    /// 保存封面图片
    private func saveCoverImage(jpegData: Data) throws {
        let coverPath = try coverManager.saveCover(data: jpegData, sessionId: sessionId)

        // 更新 SessionRecord 的 coverImagePath
        if let record = SessionRecordManager.shared.loadSession(id: sessionId) {
            let updatedRecord = record.withCoverImagePath(coverPath)

            let sessionDir = SessionRecordManager.shared.sessionsDirectory
                .appendingPathComponent(sessionId, isDirectory: true)
            let recordURL = sessionDir.appendingPathComponent("record.json")

            let recordData = try JSONEncoder().encode(updatedRecord)
            try recordData.write(to: recordURL)

            // 更新 metadata
            let metadata = SessionRecordMetadata(from: updatedRecord)
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL)

            SessionRecordManager.shared.invalidateMetadataCache()
        }

        NotificationCenter.default.post(
            name: Constants.NotificationNames.coverImageDidUpdate,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
        Self.logger.info("封面保存成功: session=\(sessionId)")
    }

    /// 保存头像图片
    private func saveAvatarImage(jpegData: Data) throws {
        let sessionDir = SessionRecordManager.shared.sessionsDirectory
            .appendingPathComponent(sessionId, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent("avatar.jpg")

        try jpegData.write(to: avatarURL)

        NotificationCenter.default.post(
            name: Constants.NotificationNames.avatarImageDidUpdate,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
        Self.logger.info("头像保存成功: session=\(sessionId)")
    }
}

// MARK: - 裁剪覆盖层视图
struct CropOverlayView: View {
    let cropWidth: CGFloat
    let cropHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let containerW = geometry.size.width
            let containerH = geometry.size.height

            let cropX = (containerW - cropWidth) / 2
            let cropY = (containerH - cropHeight) / 2
            let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)

            // 预计算网格线位置
            let thirdW = cropWidth / 3
            let thirdH = cropHeight / 3

            ZStack {
                // 黑色遮罩（裁剪框外，使用 eoFill 确保镂空）
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRect(cropRect)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                // 裁剪框边框
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropWidth, height: cropHeight)
                    .position(x: containerW / 2, y: containerH / 2)

                // 3x3 网格线
                Path { path in
                    // 垂直线
                    for i in 1...2 {
                        let x = cropX + thirdW * CGFloat(i)
                        path.move(to: CGPoint(x: x, y: cropY))
                        path.addLine(to: CGPoint(x: x, y: cropY + cropHeight))
                    }
                    // 水平线
                    for i in 1...2 {
                        let y = cropY + thirdH * CGFloat(i)
                        path.move(to: CGPoint(x: cropX, y: y))
                        path.addLine(to: CGPoint(x: cropX + cropWidth, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
            }
            .compositingGroup()
        }
    }
}

// MARK: - Preview

#Preview {
    CoverEditView(sessionId: "test-session-id", editMode: .cover, imageIndex: 0) {
        // Dismiss action
    }
}
