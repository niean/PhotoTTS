import SwiftUI
import UIKit
import PhotosUI
import os.log

struct SessionImageEditView: View {
    let sessionId: String
    let imageIndex: Int
    let onDismiss: () -> Void
    let onSave: () -> Void

    @State private var rotation: Int = 0
    @State private var originalImage: UIImage?
    @State private var editedSourceImage: UIImage?
    @State private var imageOffset: CGSize = .zero
    @State private var imageScale: CGFloat = 1.0
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var previewContainerSize: CGSize = .zero
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showError = false

    private static let logger = os.Logger.makeView

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else if let image = editedSourceImage {
                    VStack(spacing: 20) {
                        imagePreviewSection(image: image)
                        controlButtonsSection
                        bottomButtonsSection
                    }
                    .padding()
                } else {
                    Text("无法加载图片")
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("编辑图片")
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
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            loadPickedImage(from: newItem)
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private func imagePreviewSection(image: UIImage) -> some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let containerHeight = geometry.size.height
            let imageAspect = max(image.size.width / max(image.size.height, 1), 0.1)

            let displaySize = calculateDisplaySize(
                imageAspect: imageAspect,
                containerWidth: containerWidth,
                containerHeight: containerHeight
            )
            let displayWidth = displaySize.width
            let displayHeight = displaySize.height

            let cropSize = calculateCropSize(
                width: displayWidth,
                height: displayHeight,
                aspectRatio: imageAspect
            )

            let combinedScale = clampValue(imageScale * pinchScale, min: 1.0, max: 3.0)
            let scaledDisplayWidth = displayWidth * combinedScale
            let scaledDisplayHeight = displayHeight * combinedScale
            let maxOffsetX = max((scaledDisplayWidth - cropSize.width) / 2, 0)
            let maxOffsetY = max((scaledDisplayHeight - cropSize.height) / 2, 0)
            let combinedOffset = CGSize(
                width: clampValue(imageOffset.width + dragOffset.width, min: -maxOffsetX, max: maxOffsetX),
                height: clampValue(imageOffset.height + dragOffset.height, min: -maxOffsetY, max: maxOffsetY)
            )

            let dragGesture = DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let currentScale = clampValue(imageScale, min: 1.0, max: 3.0)
                    let maxX = max((displayWidth * currentScale - cropSize.width) / 2, 0)
                    let maxY = max((displayHeight * currentScale - cropSize.height) / 2, 0)
                    imageOffset = CGSize(
                        width: clampValue(imageOffset.width + value.translation.width, min: -maxX, max: maxX),
                        height: clampValue(imageOffset.height + value.translation.height, min: -maxY, max: maxY)
                    )
                }

            let magnifyGesture = MagnificationGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    let newScale = clampValue(imageScale * value, min: 1.0, max: 3.0)
                    imageScale = newScale
                    let maxX = max((displayWidth * newScale - cropSize.width) / 2, 0)
                    let maxY = max((displayHeight * newScale - cropSize.height) / 2, 0)
                    imageOffset = CGSize(
                        width: clampValue(imageOffset.width, min: -maxX, max: maxX),
                        height: clampValue(imageOffset.height, min: -maxY, max: maxY)
                    )
                }

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displayWidth, height: displayHeight)
                    .scaleEffect(combinedScale)
                    .offset(combinedOffset)

                CropOverlayView(cropWidth: cropSize.width, cropHeight: cropSize.height)
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

    private var controlButtonsSection: some View {
        HStack(spacing: 28) {
            Button(action: rotateImage) {
                controlButton(icon: "rotate.left", title: "旋转")
            }

            Button(action: resetImageState) {
                controlButton(icon: "arrow.counterclockwise", title: "重置")
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                controlButton(icon: "photo.badge.plus", title: "上传新图")
            }
        }
    }

    private func controlButton(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(Constants.Fonts.coverEditIcon)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
            Text(title)
                .font(Constants.Fonts.caption)
                .foregroundColor(.white)
        }
    }

    private var bottomButtonsSection: some View {
        HStack(spacing: 20) {
            Button(action: onDismiss) {
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
                        Text("保存")
                            .font(Constants.Fonts.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isSaving || isLoading || editedSourceImage == nil)
        }
    }

    private func clampValue(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func calculateDisplaySize(imageAspect: CGFloat, containerWidth: CGFloat, containerHeight: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let containerAspect = containerWidth / max(containerHeight, 1)
        if imageAspect > containerAspect {
            return (containerWidth, containerWidth / imageAspect)
        }
        return (containerHeight * imageAspect, containerHeight)
    }

    private func calculateCropSize(width: CGFloat, height: CGFloat, aspectRatio: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let imageAspect = width / max(height, 1)
        if imageAspect > aspectRatio {
            return (height * aspectRatio, height)
        }
        return (width, width / aspectRatio)
    }

    private func loadOriginalImage() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = SessionRecordManager.shared.loadImage(
                sessionId: sessionId,
                index: imageIndex,
                maxDimension: Constants.ImageDisplay.saveImageMaxPixel
            )
            DispatchQueue.main.async {
                self.originalImage = loaded
                self.editedSourceImage = loaded
                self.isLoading = false
                if loaded == nil {
                    self.errorMessage = "无法加载图片"
                    self.showError = true
                }
            }
        }
    }

    private func loadPickedImage(from item: PhotosPickerItem) {
        isLoading = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "无法读取选中的图片"
                        showError = true
                    }
                    return
                }

                let maxPixel = Int(Constants.ImageDisplay.saveImageMaxPixel)
                let normalized = SessionRecordManager.downsampleImageToMaxPixel(image, maxPixelLength: maxPixel) ?? image

                await MainActor.run {
                    originalImage = normalized
                    editedSourceImage = normalized
                    selectedPhotoItem = nil
                    resetTransformOnly()
                    isLoading = false
                }
            } catch {
                Self.logger.error("读取新图片失败: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    errorMessage = "读取新图片失败"
                    showError = true
                }
            }
        }
    }

    private func rotateImage() {
        rotation = (rotation + 90) % 360
        imageOffset = .zero
        imageScale = 1.0
        applyRotation()
    }

    private func resetImageState() {
        editedSourceImage = originalImage
        resetTransformOnly()
    }

    private func resetTransformOnly() {
        rotation = 0
        imageOffset = .zero
        imageScale = 1.0
    }

    private func applyRotation() {
        guard let originalImage else { return }
        if rotation == 0 {
            editedSourceImage = originalImage
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard var ciImage = CIImage(image: originalImage) else {
                DispatchQueue.main.async {
                    editedSourceImage = originalImage
                }
                return
            }

            let radians = CGFloat(rotation) * .pi / 180
            ciImage = ciImage.transformed(by: CGAffineTransform(rotationAngle: radians))

            let extent = ciImage.extent
            ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))

            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                DispatchQueue.main.async {
                    editedSourceImage = originalImage
                }
                return
            }

            DispatchQueue.main.async {
                editedSourceImage = UIImage(cgImage: cgImage)
            }
        }
    }

    private func saveImage() {
        guard let image = editedSourceImage,
              previewContainerSize.width > 0,
              let ciImage = CIImage(image: image) else {
            errorMessage = "图片处理失败"
            showError = true
            return
        }

        isSaving = true

        let capturedOffset = imageOffset
        let capturedScale = imageScale
        let capturedContainerSize = previewContainerSize

        Task {
            do {
                let imageWidth = ciImage.extent.width
                let imageHeight = ciImage.extent.height
                let imageAspect = imageWidth / max(imageHeight, 1)

                let displaySize = calculateDisplaySize(
                    imageAspect: imageAspect,
                    containerWidth: capturedContainerSize.width,
                    containerHeight: capturedContainerSize.height
                )
                let cropDisplay = calculateCropSize(
                    width: displaySize.width,
                    height: displaySize.height,
                    aspectRatio: imageAspect
                )

                let effectiveScale = imageWidth / (displaySize.width * capturedScale)
                let cropWidth = cropDisplay.width * effectiveScale
                let cropHeight = cropDisplay.height * effectiveScale
                let cropX = (imageWidth - cropWidth) / 2 - capturedOffset.width * effectiveScale
                let cropY = (imageHeight - cropHeight) / 2 + capturedOffset.height * effectiveScale

                var cropped = ciImage.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
                let extent = cropped.extent
                cropped = cropped.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))

                let context = CIContext()
                guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
                    throw NSError(
                        domain: Constants.ErrorInfo.domain,
                        code: Constants.ErrorInfo.defaultCode,
                        userInfo: [NSLocalizedDescriptionKey: "图片处理失败"]
                    )
                }

                let finalImage = UIImage(cgImage: cgImage)
                let success = SessionRecordManager.shared.replaceSessionImage(
                    sessionId: sessionId,
                    index: imageIndex,
                    image: finalImage
                )

                guard success else {
                    throw NSError(
                        domain: Constants.ErrorInfo.domain,
                        code: Constants.ErrorInfo.defaultCode,
                        userInfo: [NSLocalizedDescriptionKey: "保存失败"]
                    )
                }

                NotificationCenter.default.post(
                    name: Constants.NotificationNames.sessionImageDidUpdate,
                    object: nil,
                    userInfo: ["sessionId": sessionId, "index": imageIndex]
                )
                NotificationCenter.default.post(
                    name: Constants.NotificationNames.sessionMetadataDidUpdate,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
                if imageIndex == 0 {
                    NotificationCenter.default.post(
                        name: Constants.NotificationNames.avatarImageDidUpdate,
                        object: nil,
                        userInfo: ["sessionId": sessionId]
                    )
                    NotificationCenter.default.post(
                        name: Constants.NotificationNames.coverImageDidUpdate,
                        object: nil,
                        userInfo: ["sessionId": sessionId]
                    )
                }

                await MainActor.run {
                    isSaving = false
                    onSave()
                    onDismiss()
                }
            } catch {
                Self.logger.error("保存编辑后的会话图片失败: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    errorMessage = "保存失败"
                    showError = true
                }
            }
        }
    }
}
