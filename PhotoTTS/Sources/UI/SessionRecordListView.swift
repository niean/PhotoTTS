import SwiftUI
import UIKit
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
    @State private var showImportPicker = false  // 显示导入文件夹选择器
    @State private var exportItem: SessionExportableURL?  // 导出分享项
    @State private var isImporting = false  // 导入状态
    @State private var showMessage = false  // 显示操作结果提示
    @State private var message = ""  // 操作结果消息
    @State private var needReloadAfterMessage = false  // 提示关闭后是否需要刷新列表
    @State private var showClearConfirmation = false  // 显示清空确认弹窗
    
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
                                    onLoad: (allowPlayback && !metadata.isMaking) ? { loadSession(metadata.id) } : nil,
                                    onLoadToMake: (mode == .manage && onLoadToMake != nil) ? { onLoadToMake?(metadata.id) } : nil,
                                    onView: !metadata.isMaking ? {
                                        viewSessionDetail(metadata.id)
                                    } : nil,
                                    onEdit: (allowEditDelete && !metadata.isMaking) ? { editSessionDetail(metadata.id) } : nil,
                                    onExport: (allowEditDelete && !metadata.isMaking) ? { exportOneSession(id: metadata.id) } : nil,
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
                        Menu {
                            Button(action: { showImportPicker = true }) {
                                Label("导入", systemImage: "square.and.arrow.down")
                            }
                            Divider()
                            Button(action: { exportToShareSheet() }) {
                                Label("导出", systemImage: "square.and.arrow.up")
                            }
                            .disabled(sessionMetadataList.isEmpty)
                            Divider()
                            Button(role: .destructive, action: { showClearConfirmation = true }) {
                                Label("清空", systemImage: "trash")
                            }
                            .disabled(sessionMetadataList.isEmpty)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: isPad ? 24 : 22))
                                .foregroundColor(.blue)
                                .background(Color.clear)
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
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importSessions(from: url)
            case .failure:
                message = "选择文件夹失败"
                showMessage = true
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheetView(activityItems: [item.url])
                .onDisappear {
                    // 清理临时导出目录
                    try? FileManager.default.removeItem(at: item.url)
                }
        }
        .overlay {
            if isImporting {
                CustomZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("正在导入...").font(.headline).foregroundColor(.white)
                    }
                }
            }
        }
        .alert("提示", isPresented: $showMessage) {
            Button("确定", role: .cancel) {
                if needReloadAfterMessage {
                    needReloadAfterMessage = false
                    loadSessionList()
                }
            }
        } message: {
            Text(message)
        }
        .alert("清空所有记录", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearAllSessions()
            }
        } message: {
            Text("确定要清空所有会话记录吗？")
        }
    }
    
    // 加载会话记录列表
    private func loadSessionList() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let metadataList = SessionRecordManager.shared.getAllSessionMetadata(caller: "记录列表")
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
                    let duplicate = result.duplicateCount
                    let skipped = result.skippedCount
                    let total = imported + duplicate + skipped
                    let formattedSize = self.formatStorageSize(result.totalSize)
                    
                    var msg = "共 \(total) 个，导入 \(imported) 个"
                    if duplicate > 0 {
                        msg += "\nID重复跳过 \(duplicate) 个"
                    }
                    if skipped > 0 {
                        msg += "\n其他原因跳过 \(skipped) 个"
                    }
                    if imported > 0 {
                        msg += "\n总大小: \(formattedSize)"
                    }
                    
                    self.message = msg
                    self.needReloadAfterMessage = imported > 0
                    self.showMessage = true
                } else {
                    self.message = "导入失败: \(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                }
            }
        }
    }
    
    // 导出所有会话记录到临时目录，然后通过分享面板分享
    private func exportToShareSheet() {
        guard !sessionMetadataList.isEmpty else {
            message = "没有可导出的会话记录"
            showMessage = true
            return
        }
        
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 创建临时目录作为导出目标
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoTTS_SessionExport_\(UUID().uuidString.prefix(8))", isDirectory: true)
            
            // 执行导出操作
            let result = SessionRecordManager.shared.exportAllSessions(to: tempBase)
            
            DispatchQueue.main.async {
                self.isExporting = false
                
                if result.success {
                    // 查找导出目录（exportAllSessions 会在 tempBase 下创建 PhotoTTS_yyyyMMdd 子目录）
                    if let contents = try? FileManager.default.contentsOfDirectory(at: tempBase, includingPropertiesForKeys: nil),
                       let exportDir = contents.first {
                        self.exportItem = SessionExportableURL(url: exportDir)
                    } else {
                        self.exportItem = SessionExportableURL(url: tempBase)
                    }
                } else {
                    self.message = "导出失败: \(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                    // 清理临时目录
                    try? FileManager.default.removeItem(at: tempBase)
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

    // 导出单条会话记录到临时目录，然后通过分享面板分享
    private func exportOneSession(id: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let tempBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("PhotoTTS_OneExport_\(UUID().uuidString.prefix(8))", isDirectory: true)
            let result = SessionRecordManager.shared.exportSession(id: id, to: tempBase)
            DispatchQueue.main.async {
                if result.success {
                    // exportSession 在 tempBase 下创建以记录名称命名的子目录
                    if let contents = try? FileManager.default.contentsOfDirectory(at: tempBase, includingPropertiesForKeys: nil),
                       let exportDir = contents.first {
                        self.exportItem = SessionExportableURL(url: exportDir)
                    } else {
                        self.exportItem = SessionExportableURL(url: tempBase)
                    }
                } else {
                    self.message = "导出失败: \(result.errorMessage ?? "未知错误")"
                    self.showMessage = true
                    try? FileManager.default.removeItem(at: tempBase)
                }
            }
        }
    }

    // 清空所有会话记录
    private func clearAllSessions() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SessionRecordManager.shared.clearAllSessions()
            DispatchQueue.main.async {
                if result.success {
                    self.message = "已清空 \(result.count) 个会话记录"
                } else {
                    self.message = result.errorMessage ?? "清空失败"
                }
                self.needReloadAfterMessage = true
                self.showMessage = true
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
    let onView: (() -> Void)?
    let onEdit: (() -> Void)?
    let onExport: (() -> Void)?
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
                    if metadata.isMaking {
                        Text("制作中")
                            .font(isPad ? .subheadline : .caption)
                            .foregroundColor(.orange)
                    } else {
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
                    if let onView = onView {
                        Button(action: onView) {
                            Label("查看", systemImage: "eye.circle")
                        }
                    }
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Label("编辑", systemImage: "pencil")
                        }
                    }
                    if let onExport = onExport {
                        Button(action: onExport) {
                            Label("导出", systemImage: "square.and.arrow.up")
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
        let avatarIdx = min(max(0, metadata.avatarImageIndex), metadata.totalImageCount - 1)
        loadingId = sid
        DispatchQueue.global(qos: .utility).async {
            // 优先加载预生成的 avatar.jpg
            if let avatar = SessionRecordManager.shared.loadAvatar(sessionId: sid) {
                DispatchQueue.main.async {
                    if loadingId == sid { avatarImage = avatar }
                }
                return
            }
            // 回退：从原图按需生成，并写回 avatar.jpg 供下次直接命中
            let fallback = SessionRecordManager.shared.loadImage(sessionId: sid, index: avatarIdx, maxDimension: Self.rowAvatarMaxDimension)
                ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: 0, maxDimension: Self.rowAvatarMaxDimension)
            if let img = fallback {
                SessionRecordManager.shared.saveAvatarIfMissing(sessionId: sid, image: img)
            }
            DispatchQueue.main.async {
                if loadingId == sid { avatarImage = fallback }
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

// MARK: - 导出文件包装（用于 .sheet(item:) 触发分享面板）
private struct SessionExportableURL: Identifiable {
    let id = UUID()
    let url: URL
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

