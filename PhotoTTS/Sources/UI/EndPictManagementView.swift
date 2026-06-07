import SwiftUI
import PhotosUI

// MARK: - 要点图片管理页面
struct EndPictManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var horizontalImages: [EndPictItem] = []
    @State private var verticalImages: [EndPictItem] = []
    @State private var showImagePicker = false
    @State private var selectedDirection: String? = nil
    @State private var showDeleteConfirm = false
    @State private var itemToDelete: EndPictItem? = nil
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showFullScreen: Bool = false
    @State private var fullScreenItems: [EndPictItem] = []
    @State private var fullScreenIndex: Int = 0

    private let thumbnailSize: CGFloat = 80
    private let gridSpacing: CGFloat = 12

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: scaled(24)) {
                    // 横向图片组
                    EndPictSectionView(
                        title: "横向动画",
                        subtitle: "从右向左翻页时显示",
                        items: $horizontalImages,
                        thumbnailSize: thumbnailSize,
                        gridSpacing: gridSpacing,
                        direction: Constants.EndPicts.horizontalDirectoryName,
                        onAdd: {
                            selectedDirection = Constants.EndPicts.horizontalDirectoryName
                            showImagePicker = true
                        },
                        onDelete: { item in
                            itemToDelete = item
                            showDeleteConfirm = true
                        },
                        onTap: { item in
                            if let idx = horizontalImages.firstIndex(where: { $0.id == item.id }) {
                                fullScreenItems = horizontalImages
                                fullScreenIndex = idx
                                showFullScreen = true
                            }
                        }
                    )

                    Divider()
                        .padding(.horizontal, scaled(16))

                    // 纵向图片组
                    EndPictSectionView(
                        title: "纵向动画",
                        subtitle: "从上向下翻页时显示",
                        items: $verticalImages,
                        thumbnailSize: thumbnailSize,
                        gridSpacing: gridSpacing,
                        direction: Constants.EndPicts.verticalDirectoryName,
                        onAdd: {
                            selectedDirection = Constants.EndPicts.verticalDirectoryName
                            showImagePicker = true
                        },
                        onDelete: { item in
                            itemToDelete = item
                            showDeleteConfirm = true
                        },
                        onTap: { item in
                            if let idx = verticalImages.firstIndex(where: { $0.id == item.id }) {
                                fullScreenItems = verticalImages
                                fullScreenIndex = idx
                                showFullScreen = true
                            }
                        }
                    )
                }
                .padding(.top, scaled(60))
                .padding(.horizontal, scaled(16))
                .padding(.bottom, scaled(24))
            }
            .background(Color(.systemGroupedBackground))

            // 导航栏+状态栏背景遮罩，防止滚动内容透过
            GeometryReader { proxy in
                Color(.systemGroupedBackground)
                    .frame(height: proxy.safeAreaInsets.top + scaled(60))
                    .ignoresSafeArea(.all, edges: .top)
            }
            .allowsHitTesting(false)

            TopAndLeftSideNavigationBar(title: "要点图片", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.navAction)
                        .frame(width: scaled(20), height: scaled(20))
                        .foregroundStyle(.primary)
                }
            })
        }
        .navigationBarHidden(true)
        .onAppear { loadImages() }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerForEndPict { images in
                if let direction = selectedDirection {
                    saveImages(images, direction: direction)
                }
            }
        }
        .alert("删除图片", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let item = itemToDelete {
                    deleteItem(item)
                }
            }
        } message: {
            Text("确定要删除这张图片吗？")
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenEndPictView(items: $fullScreenItems, currentIndex: $fullScreenIndex) {
                showFullScreen = false
            }
        }
        .overlay {
            if showToast {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(Constants.Fonts.subheadline)
                        .padding(.horizontal, scaled(16))
                        .padding(.vertical, scaled(12))
                        .background(.regularMaterial)
                        .cornerRadius(scaled(10))
                        .padding(.bottom, scaled(40))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: showToast)
            }
        }
    }

    private func loadImages() {
        let hDirection = Constants.EndPicts.horizontalDirectoryName
        let vDirection = Constants.EndPicts.verticalDirectoryName

        var hItems: [EndPictItem] = []
        var vItems: [EndPictItem] = []

        // 横向系统图片（动态扫描）
        let hResourceNames = SessionRecordManager.shared.systemEndPictResourceNames(direction: hDirection)
        for (i, name) in hResourceNames.enumerated() {
            if let thumbnail = SessionRecordManager.shared.loadSystemEndPictThumbnail(direction: hDirection, index: i) {
                hItems.append(EndPictItem(id: "system-\(name)", thumbnail: thumbnail, isSystem: true, url: nil, resourceName: name))
            }
        }

        // 纵向系统图片（动态扫描）
        let vResourceNames = SessionRecordManager.shared.systemEndPictResourceNames(direction: vDirection)
        for (i, name) in vResourceNames.enumerated() {
            if let thumbnail = SessionRecordManager.shared.loadSystemEndPictThumbnail(direction: vDirection, index: i) {
                vItems.append(EndPictItem(id: "system-\(name)", thumbnail: thumbnail, isSystem: true, url: nil, resourceName: name))
            }
        }

        // 加载用户上传图片
        let hUserURLs = SessionRecordManager.shared.getUserEndPictURLs(direction: hDirection)
        for url in hUserURLs {
            if let thumbnail = SessionRecordManager.shared.loadUserEndPictThumbnail(url: url) {
                hItems.append(EndPictItem(id: url.path, thumbnail: thumbnail, isSystem: false, url: url, resourceName: nil))
            }
        }

        let vUserURLs = SessionRecordManager.shared.getUserEndPictURLs(direction: vDirection)
        for url in vUserURLs {
            if let thumbnail = SessionRecordManager.shared.loadUserEndPictThumbnail(url: url) {
                vItems.append(EndPictItem(id: url.path, thumbnail: thumbnail, isSystem: false, url: url, resourceName: nil))
            }
        }

        horizontalImages = hItems
        verticalImages = vItems
    }

    private func saveImages(_ images: [UIImage], direction: String) {
        var successCount = 0
        for image in images {
            if SessionRecordManager.shared.saveUserEndPict(image: image, direction: direction) {
                successCount += 1
            }
        }
        if successCount == images.count {
            showToastMessage("已添加 \(successCount) 张图片")
        } else if successCount > 0 {
            showToastMessage("已添加 \(successCount)/\(images.count) 张")
        } else {
            showToastMessage("添加失败")
        }
        loadImages()
    }

    private func deleteItem(_ item: EndPictItem) {
        guard !item.isSystem, let url = item.url else { return }
        let success = SessionRecordManager.shared.deleteUserEndPict(url: url)
        if success {
            showToastMessage("图片已删除")
            loadImages()
        } else {
            showToastMessage("删除失败")
        }
    }

    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showToast = false
            }
        }
    }
}

// MARK: - 要点图片项
struct EndPictItem: Identifiable {
    let id: String
    let thumbnail: UIImage
    let isSystem: Bool
    let url: URL?
    /// 系统图片的 Bundle 资源名（不含扩展名），用户图片为 nil
    let resourceName: String?
}

// MARK: - 要点图片分组视图
struct EndPictSectionView: View {
    let title: String
    let subtitle: String
    @Binding var items: [EndPictItem]
    let thumbnailSize: CGFloat
    let gridSpacing: CGFloat
    let direction: String
    let onAdd: () -> Void
    let onDelete: (EndPictItem) -> Void
    let onTap: (EndPictItem) -> Void

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: scaled(12)) {
            // 标题
            VStack(alignment: .leading, spacing: scaled(4)) {
                Text(title)
                    .font(Constants.Fonts.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(Constants.Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            // 图片网格
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize), spacing: gridSpacing)
            ], spacing: gridSpacing) {
                ForEach(items) { item in
                    EndPictThumbnailView(
                        item: item,
                        size: thumbnailSize,
                        onDelete: { onDelete(item) },
                        onTap: { onTap(item) }
                    )
                }
            }

            // 添加按钮
            Button(action: onAdd) {
                HStack {
                    Spacer()
                    Label("添加图片", systemImage: "plus.circle")
                        .font(Constants.Fonts.subheadline)
                    Spacer()
                }
                .padding(.vertical, scaled(12))
                .background(Color(.systemBackground))
                .cornerRadius(scaled(10))
            }
            .buttonStyle(.plain)

            // 播放队列区段
            EndPictQueueSectionView(
                direction: direction,
                thumbnailSize: thumbnailSize,
                gridSpacing: gridSpacing
            )
            .padding(.top, scaled(16))
        }
    }
}

// MARK: - 要点图片缩略图视图
struct EndPictThumbnailView: View {
    let item: EndPictItem
    let size: CGFloat
    let onDelete: () -> Void
    let onTap: () -> Void

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: scaled(8)))
                .onTapGesture { onTap() }

            // 系统标签或删除按钮
            if item.isSystem {
                Text("系统")
                    .font(.system(size: 10)) // 视图私有：角标小字体，固定 10pt 适配缩略图尺寸
                    .padding(.horizontal, scaled(6))
                    .padding(.vertical, scaled(2))
                    .background(Color(.systemGray4))
                    .foregroundColor(.white)
                    .cornerRadius(scaled(4))
                    .offset(x: scaled(-4), y: scaled(4))
            } else {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scaled(22))) // 视图私有：删除图标，动态缩放适配缩略图
                        .foregroundColor(.gray)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: scaled(-4), y: scaled(4))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 图片选择器（用于要点图片，支持多选）
struct ImagePickerForEndPict: UIViewControllerRepresentable {
    let onImagesPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 0 // 0 = 不限数量

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesPicked: ([UIImage]) -> Void

        init(onImagesPicked: @escaping ([UIImage]) -> Void) {
            self.onImagesPicked = onImagesPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard !results.isEmpty else { return }

            let group = DispatchGroup()
            var images: [(Int, UIImage)] = []
            let lock = NSLock()

            for (index, result) in results.enumerated() {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        lock.lock()
                        images.append((index, image))
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                let sorted = images.sorted { $0.0 < $1.0 }.map { $0.1 }
                self.onImagesPicked(sorted)
            }
        }
    }
}

// MARK: - 全屏原图查看（支持左右滑动切换）
struct FullScreenEndPictView: View {
    @Binding var items: [EndPictItem]
    @Binding var currentIndex: Int
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage? = nil

    private static let maxDim = Constants.ImageDisplay.playbackFullScreenMaxDimension

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                // 中层：模糊背景（与播放器一致：.fit + scaleEffect）
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(Constants.ImageDisplay.blurBackgroundScaleEffect)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: Constants.ImageDisplay.blurBackgroundRadius)
                        .opacity(Constants.ImageDisplay.blurBackgroundOpacity)
                        .clipped()
                }

                // 顶层：原图（与播放器一致：圆角 8pt）
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    ProgressView()
                        .tint(.primary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .gesture(
                DragGesture(minimumDistance: Constants.Gesture.swipeMinDistance)
                    .onEnded { value in
                        let t = value.translation.width
                        if t < -Constants.Gesture.swipeMinDistance, currentIndex < items.count - 1 {
                            currentIndex += 1
                        } else if t > Constants.Gesture.swipeMinDistance, currentIndex > 0 {
                            currentIndex -= 1
                        }
                    }
            )
        }
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
        .onAppear { loadImage(for: currentIndex) }
        .onChange(of: currentIndex) { _, newIndex in
            loadImage(for: newIndex)
        }
    }

    private func loadImage(for index: Int) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        if item.isSystem, let resourceName = item.resourceName {
            let imageURL = Bundle.main.url(forResource: resourceName, withExtension: "jpg")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "png")
            if let imageURL {
                loadedImage = SessionRecordManager.shared.loadUserEndPictThumbnail(url: imageURL, maxDimension: Self.maxDim)
            }
        } else if let url = item.url {
            loadedImage = SessionRecordManager.shared.loadUserEndPictThumbnail(url: url, maxDimension: Self.maxDim)
        }
    }
}

// MARK: - 要点图片队列项视图
private struct EndPictQueueItemView: View {
    let item: SessionRecordManager.EndPictQueueItem
    let queueNumber: Int
    let isNext: Bool
    let isPlayed: Bool
    let size: CGFloat

    @State private var loadedImage: UIImage? = nil

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 图片
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: scaled(8)))
                    .opacity(isPlayed ? 0.5 : 1.0)
            } else {
                RoundedRectangle(cornerRadius: scaled(8))
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .tint(.secondary)
                    }
            }

            // 序号标记
            ZStack {
                Circle()
                    .fill(isPlayed ? Color.gray : Color.blue)
                    .frame(width: scaled(24), height: scaled(24))
                Text("\(queueNumber)")
                    .font(Constants.Fonts.endPictQueueNumber)
                    .foregroundColor(.white)
            }
            .offset(x: scaled(4), y: scaled(4))
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: scaled(8))
                .stroke(isNext ? Color.orange : Color.clear, lineWidth: scaled(2))
        )
        .overlay(
            // 下一张标签
            Group {
                if isNext {
                    Text("下一张")
                        .font(.system(size: scaled(10)))
                        .foregroundColor(.white)
                        .padding(.horizontal, scaled(6))
                        .padding(.vertical, scaled(2))
                        .background(Color.orange)
                        .cornerRadius(scaled(4))
                        .offset(y: scaled(size/2 - 14))
                }
            }
        )
        .onAppear {
            if loadedImage == nil {
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = SessionRecordManager.shared.getEndPictItemThumbnail(
                        item: item,
                        maxDimension: Constants.EndPicts.thumbnailMaxDimension
                    )
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            loadedImage = img
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 要点图片队列区段视图
private struct EndPictQueueSectionView: View {
    let direction: String
    let thumbnailSize: CGFloat
    let gridSpacing: CGFloat

    @State private var queueInfo: SessionRecordManager.EndPictQueueInfo? = nil
    @State private var refreshId = UUID()

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    /// 构建合并后的显示队列（已播 + 待播）
    private func combinedDisplayItems(_ queueInfo: SessionRecordManager.EndPictQueueInfo) -> [(item: SessionRecordManager.EndPictQueueItem, displayNumber: Int, isNext: Bool, isPlayed: Bool)] {
        var result: [(item: SessionRecordManager.EndPictQueueItem, displayNumber: Int, isNext: Bool, isPlayed: Bool)] = []

        // 已播图片：编号从 1 开始
        for (playedIdx, itemIdx) in queueInfo.playedIndices.enumerated() {
            if itemIdx < queueInfo.items.count {
                result.append((
                    item: queueInfo.items[itemIdx],
                    displayNumber: playedIdx + 1,
                    isNext: false,
                    isPlayed: true
                ))
            }
        }

        // 待播图片：编号从 (已播数量 + 1) 开始
        let playedCount = queueInfo.playedIndices.count
        for (queueIdx, itemIdx) in queueInfo.queue.enumerated() {
            if itemIdx < queueInfo.items.count {
                result.append((
                    item: queueInfo.items[itemIdx],
                    displayNumber: playedCount + queueIdx + 1,
                    isNext: queueIdx == queueInfo.nextQueueIndex,
                    isPlayed: false
                ))
            }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: scaled(12)) {
            if let queueInfo = queueInfo, !(queueInfo.queue.isEmpty && queueInfo.playedIndices.isEmpty) {
                // 分割线
                Divider()

                // 标题
                Text("播放队列")
                    .font(Constants.Fonts.caption)
                    .foregroundStyle(.secondary)

                // 队列网格（已播 + 待播合并展示）
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize), spacing: gridSpacing)
                ], spacing: gridSpacing) {
                    ForEach(Array(combinedDisplayItems(queueInfo).enumerated()), id: \.offset) { _, displayItem in
                        EndPictQueueItemView(
                            item: displayItem.item,
                            queueNumber: displayItem.displayNumber,
                            isNext: displayItem.isNext,
                            isPlayed: displayItem.isPlayed,
                            size: thumbnailSize
                        )
                    }
                }

                // 重置按钮
                Button(action: {
                    SessionRecordManager.shared.resetEndPictQueue(direction: direction)
                    refreshId = UUID()
                    loadQueueInfo()
                }) {
                    HStack {
                        Spacer()
                        Label("重置队列", systemImage: "arrow.clockwise")
                            .font(Constants.Fonts.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, scaled(12))
                    .background(Color(.systemBackground))
                    .cornerRadius(scaled(10))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            loadQueueInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            loadQueueInfo()
        }
        .id(refreshId)
    }

    private func loadQueueInfo() {
        queueInfo = SessionRecordManager.shared.getEndPictQueueInfo(direction: direction)
    }
}
