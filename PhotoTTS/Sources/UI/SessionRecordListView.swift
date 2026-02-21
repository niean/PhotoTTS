import SwiftUI
import UniformTypeIdentifiers

// MARK: - 会话记录列表展示模式
/// 标准：顶导 + 全部功能（播放、查看、编辑、删除、导入导出）
/// 嵌入：无顶导，仅播放、查看
/// 管理：顶导 + 查看、编辑、删除（不允许播放）、导入导出
enum SessionRecordListMode {
    case standard
    case embedded
    case manage
}

// MARK: - 会话记录列表视图
struct SessionRecordListView: View {
    @State private var sessionMetadataList: [SessionRecordMetadata] = []
    @State private var isLoading = true
    @State private var showDeleteConfirmation = false
    @State private var sessionToDelete: SessionRecordMetadata?
    @State private var sessionToEditRecord: SessionRecord?  // 编辑时加载的完整记录
    @State private var isLoadingSession = false  // 加载会话记录时的加载状态
    @State private var showSessionDetail = false  // 显示会话详情
    @State private var sessionToView: SessionRecord?  // 要查看的会话记录
    @State private var isExporting = false  // 导出状态
    @State private var showExportSuccess = false  // 显示导出成功提示
    @State private var exportMessage = ""  // 导出消息
    @State private var showDocumentPicker = false  // 显示文档选择器
    @State private var documentPickerMode: DocumentPicker.Mode = .export  // 文档选择器模式
    @State private var isImporting = false  // 导入状态
    @State private var showImportSuccess = false  // 显示导入成功提示
    @State private var importMessage = ""  // 导入消息
    
    let onLoadSession: (SessionRecord) -> Void
    var onLoadToMake: ((String) -> Void)? = nil
    /// 展示模式
    var mode: SessionRecordListMode = .standard
    
    private var showTopNav: Bool { mode != .embedded }
    private var allowPlayback: Bool { mode != .manage }
    private var allowEditDelete: Bool { mode != .embedded }
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // 检测是否为 iPad
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // iPad 竖屏时的最大内容宽度
    private var maxContentWidth: CGFloat {
        isPad ? .infinity : .infinity
    }
    
    var body: some View {
        CustomZStack {
            // 主内容区
            HStack {
                VStack(spacing: 0) {
                    Spacer()
                    
                    if isLoading {
                        ProgressView("加载中...")
                            .scaleEffect(isPad ? 1.2 : 1.0)
                    } else if sessionMetadataList.isEmpty {
                        VStack(spacing: isPad ? 24 : 20) {
                            Image(systemName: "book.closed")
                                .font(.system(size: isPad ? 80 : 60))
                                .foregroundColor(.gray)
                            
                            Text("暂无会话记录")
                                .font(isPad ? .title2 : .headline)
                                .foregroundColor(.secondary)
                            
                            Text("导入记录，或播放完成后保存记录")
                                .font(isPad ? .subheadline : .caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        List {
                            ForEach(sessionMetadataList) { metadata in
                                SessionRecordRow(
                                    metadata: metadata,
                                    isPad: isPad,
                                    onLoad: allowPlayback ? { loadSession(metadata.id) } : nil,
                                    onLoadToMake: (mode == .manage && onLoadToMake != nil) ? { onLoadToMake?(metadata.id) } : nil,
                                    onView: {
                                        viewSessionDetail(metadata.id)
                                    },
                                    onEdit: allowEditDelete ? { editSessionDetail(metadata.id) } : nil,
                                    onDelete: allowEditDelete ? {
                                        sessionToDelete = metadata
                                        showDeleteConfirmation = true
                                    } : nil
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.top, showTopNav ? (isPad ? 50 : 45) : 8)
            }
            
            if showTopNav {
                TopAndLeftSideNavigationBar(title: "会话记录", onSwipeBack: { dismiss() }, leading: {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: isPad ? 18 : 16, weight: .medium))
                            .frame(width: isPad ? 24 : 20, height: isPad ? 24 : 20)
                            .foregroundStyle(.primary)
                    }
                }, trailing: {
                    HStack(spacing: isPad ? 20 : 16) {
                        Button(action: {
                            documentPickerMode = .`import`
                            showDocumentPicker = true
                        }) {
                            Text("导入")
                                .font(.system(size: isPad ? 17 : 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        if !sessionMetadataList.isEmpty {
                            Button(action: {
                                documentPickerMode = .export
                                showDocumentPicker = true
                            }) {
                                Text("导出")
                                    .font(.system(size: isPad ? 17 : 16, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                })
            }
        }
        .navigationBarHidden(true) // 隐藏系统导航栏
        .onAppear {
            loadSessionList()
        }
        .alert("删除会话记录", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {
                sessionToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let session = sessionToDelete {
                    deleteSession(session.id)
                }
            }
        } message: {
            if let session = sessionToDelete {
                Text("确定要删除会话记录「\(session.name)」吗？此操作无法撤销。")
            }
        }
        .navigationDestination(item: $sessionToEditRecord) { record in
            SessionRecordUnifiedView(
                mode: .edit(
                    record,
                    onSave: { newName, newAvatarIndex in
                        updateSession(id: record.id, name: newName, avatarImageIndex: newAvatarIndex) {
                            sessionToEditRecord = nil
                        }
                    },
                    onDismiss: {
                        sessionToEditRecord = nil
                    }
                )
            )
        }
        .navigationDestination(isPresented: $showSessionDetail) {
            if let record = sessionToView {
                SessionRecordUnifiedView(
                    mode: .view(record, onDismiss: {
                        showSessionDetail = false
                        sessionToView = nil
                    })
                )
            }
        }
        // 使用 fullScreenCover 避免 UIDocumentPickerViewController 在 sheet 中触发的 _UIReparentingView 层级警告
        .fullScreenCover(isPresented: $showDocumentPicker) {
            DocumentPicker(
                mode: documentPickerMode,
                onPickDirectory: { url in
                    if case .export = documentPickerMode {
                        exportAllSessions(to: url)
                    } else {
                        importSessions(from: url)
                    }
                }
            )
        }
        .overlay {
            // 导出/导入加载提示
            if isExporting || isImporting {
                CustomZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text(isExporting ? "正在导出会话记录..." : "正在导入会话记录...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
        }
        .alert("导出结果", isPresented: $showExportSuccess) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(exportMessage)
        }
        .alert("导入结果", isPresented: $showImportSuccess) {
            Button("确定", role: .cancel) {
                // 导入成功后刷新列表
                if importMessage.contains("成功") {
                    loadSessionList()
                }
            }
        } message: {
            Text(importMessage)
        }
    }
    
    // 加载会话记录列表
    private func loadSessionList() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let metadataList = SessionRecordManager.shared.getAllSessionMetadata()
            DispatchQueue.main.async {
                self.sessionMetadataList = metadataList
                self.isLoading = false
            }
        }
    }
    
    // 加载指定会话记录
    private func loadSession(_ id: String) {
        // 显示加载提示
        isLoadingSession = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    // 延迟一下，让用户看到加载提示
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isLoadingSession = false
                        onLoadSession(record)
                        if showTopNav {
                            dismiss()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoadingSession = false
                }
            }
        }
    }
    
    // 删除会话记录
    private func deleteSession(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SessionRecordManager.shared.deleteSession(id: id)
            DispatchQueue.main.async {
                if success {
                    // 重新加载列表
                    loadSessionList()
                }
            }
        }
    }
    
    // 查看会话记录详情
    private func viewSessionDetail(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    self.sessionToView = record
                    self.showSessionDetail = true
                }
            }
        }
    }
    
    // 编辑会话记录
    private func editSessionDetail(_ id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let record = SessionRecordManager.shared.loadSession(id: id) {
                DispatchQueue.main.async {
                    self.sessionToEditRecord = record
                }
            }
        }
    }
    
    // 导入会话记录：若选择导出包则全量导入，若选择单个会话目录则仅导入该条
    private func importSessions(from sourceURL: URL) {
        isImporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 在异步线程中获取访问权限
            let hasAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 执行导入操作（自动识别导出包 / 单条会话目录）
            let result = SessionRecordManager.shared.importSessions(from: sourceURL)
            
            DispatchQueue.main.async {
                self.isImporting = false
                
                if result.success {
                    let imported = result.importedCount
                    let skipped = result.skippedCount
                    let size = result.totalSize
                    let formattedSize = self.formatStorageSize(size)
                    
                    var message = "成功导入 \(imported) 个会话记录"
                    if skipped > 0 {
                        message += "\n跳过 \(skipped) 个会话记录（可能已存在）"
                    }
                    message += "\n总大小: \(formattedSize)"
                    
                    self.importMessage = message
                    self.showImportSuccess = true
                } else {
                    self.importMessage = "导入失败: \(result.errorMessage ?? "未知错误")"
                    self.showImportSuccess = true
                }
            }
        }
    }
    
    // 导出所有会话记录
    private func exportAllSessions(to destinationURL: URL) {
        guard !sessionMetadataList.isEmpty else {
            exportMessage = "没有可导出的会话记录"
            showExportSuccess = true
            return
        }
        
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 在异步线程中获取访问权限
            let hasAccess = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 执行导出操作
            let result = SessionRecordManager.shared.exportAllSessions(to: destinationURL)
            
            DispatchQueue.main.async {
                self.isExporting = false
                
                if result.success {
                    let count = result.sessionCount
                    let size = result.totalSize
                    let formattedSize = self.formatStorageSize(size)
                    // 获取导出目录名称（从完整路径中提取）
                    let exportDirName = destinationURL.lastPathComponent
                    self.exportMessage = "成功导出 \(count) 个会话记录\n总大小: \(formattedSize)\n导出位置: \(exportDirName)"
                    self.showExportSuccess = true
                } else {
                    self.exportMessage = "导出失败: \(result.errorMessage ?? "未知错误")"
                    self.showExportSuccess = true
                }
            }
        }
    }
    
    // 格式化存储大小
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 更新会话记录
    private func updateSession(id: String, name: String? = nil, avatarImageIndex: Int? = nil, completion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .userInitiated).async {
            let success = SessionRecordManager.shared.updateSession(id: id, name: name, avatarImageIndex: avatarImageIndex)
            DispatchQueue.main.async {
                if success {
                    loadSessionList()
                }
                completion()
            }
        }
    }
}

// MARK: - 会话记录行视图
struct SessionRecordRow: View {
    let metadata: SessionRecordMetadata
    let isPad: Bool
    let onLoad: (() -> Void)?
    let onLoadToMake: (() -> Void)?
    let onView: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @State private var avatarImage: UIImage? = nil
    @State private var loadingId: String? = nil
    
    var body: some View {
        HStack(spacing: isPad ? 16 : 12) {
            // 图标
            Group {
                if let avatar = avatarImage {
                    Image(uiImage: avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: isPad ? 20 : 16))
                        .foregroundColor(.blue)
                }
            }
            .frame(width: isPad ? 48 : 40, height: isPad ? 48 : 40)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: isPad ? 10 : 8))
            .onAppear {
                loadAvatarImage()
            }
            .onDisappear {
                avatarImage = nil
                loadingId = nil
            }
            
            // 信息
            VStack(alignment: .leading, spacing: isPad ? 4 : 2) {
                Text(metadata.name)
                    .font(isPad ? .title3 : .headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: isPad ? 12 : 8) {
                    Label("\(metadata.validImageCount)/\(metadata.totalImageCount)张", systemImage: "photo")
                        .labelStyle(.titleOnly)
                        .font(isPad ? .subheadline : .caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(formatDuration(metadata.audioDuration))", systemImage: "waveform")
                        .labelStyle(.titleOnly)
                        .font(isPad ? .subheadline : .caption)
                        .foregroundColor(.secondary)
                        
                    Label(formatStorageSize(metadata.storageSize), systemImage: "internaldrive")
                        .labelStyle(.titleOnly)
                        .font(isPad ? .subheadline : .caption)
                        .foregroundColor(.secondary)

                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: isPad ? 16 : 12) {
                // 加载按钮
                if let onLoad = onLoad {
                    Button(action: onLoad) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: isPad ? 24 : 20))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                }
                
                // 更多按钮
                Menu {
                    Button(action: onView) {
                        Label("查看", systemImage: "eye.circle")
                    }
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Label("编辑", systemImage: "pencil")
                        }
                    }
                    if let onLoadToMake = onLoadToMake {
                        Button(action: onLoadToMake) {
                            Label("制作", systemImage: "arrow.down.to.line.circle")
                        }
                    }
                    if let onDelete = onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Label("删除", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: isPad ? 18 : 16))
                        .foregroundColor(.gray)
                        .frame(width: isPad ? 28 : 24, height: isPad ? 28 : 24)
                }
            }
        }
        .padding(.horizontal, isPad ? 16 : 0)
        .frame(minWidth: isPad ? 48 : 40, minHeight: isPad ? 48 : 40)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
    
    /// 列表头像最大边长
    private static let rowAvatarMaxDimension: CGFloat = 120
    
    /// 加载头像
    private func loadAvatarImage() {
        guard metadata.totalImageCount > 0 else { return }
        let sid = metadata.id
        loadingId = sid
        DispatchQueue.global(qos: .utility).async {
            let image = SessionRecordManager.shared.loadAvatar(sessionId: sid)
                ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: min(max(0, metadata.avatarImageIndex), metadata.totalImageCount - 1), maxDimension: Self.rowAvatarMaxDimension)
                ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: 0, maxDimension: Self.rowAvatarMaxDimension)
            DispatchQueue.main.async {
                if loadingId == sid {
                    avatarImage = image
                }
            }
        }
    }
    
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 扩展：格式化时间
extension SessionRecordMetadata {
    var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: createdAt)
    }
}

// MARK: - 数组安全访问扩展
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 文档选择器
struct DocumentPicker: UIViewControllerRepresentable {
    enum Mode {
        case export  // 导出模式：选择目录
        case `import`  // 导入模式：选择目录
    }
    
    let mode: Mode
    let onPickDirectory: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        
        if #available(iOS 14.0, *) {
            // iOS 14+ 支持选择目录
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            // iOS 13 回退方案
            picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
        }
        
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.dismiss()
                return
            }
            
            // 将URL传递给回调，回调中会在异步线程中获取访问权限
            parent.onPickDirectory(url)
            parent.dismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - SessionRecord扩展
extension SessionRecord {
    var formattedUpdatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: updatedAt)
    }
}

