import SwiftUI
import UIKit

// MARK: - 保存上下文（用于“保存”模式）
struct SaveSessionContext {
    var suggestedName: String
    var images: [UIImage]
    var textLength: Int
    var imageCount: Int
}

// MARK: - 会话记录统一页（保存 / 编辑 / 查看 合为一页）
struct SessionRecordUnifiedView: View {
    enum Mode {
        case save(SaveSessionContext, onSave: (String, Int) -> Void, onCancel: () -> Void)
        case edit(SessionRecord, onSave: (String, Int) -> Void, onDismiss: () -> Void)
        case view(SessionRecord, onDismiss: () -> Void)
    }
    
    let mode: Mode
    @Environment(\.dismiss) var dismiss
    @State private var sessionName: String = ""
    @State private var selectedAvatarIndex: Int = 0
    @FocusState private var isTextFieldFocused: Bool
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    private var isEditable: Bool {
        switch mode {
        case .save, .edit: return true
        case .view: return false
        }
    }

    // edit / view 模式下有真实 record，返回其 id；save 模式下无 record，返回 nil
    private var recordId: String? {
        switch mode {
        case .edit(let record, _, _), .view(let record, _): return record.id
        case .save: return nil
        }
    }
    
    private var navigationTitle: String {
        switch mode {
        case .save: return "保存会话"
        case .edit: return "编辑会话"
        case .view: return "会话详情"
        }
    }
    
    var body: some View {
        CustomZStack(alignment: .leading) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // 名称
                        nameSection
                        // 头像
                        avatarSection

                        Divider()
                        
                        // 记录信息
                        contentSection
                    }
                    .padding(.horizontal, Constants.SessionDetail.contentHorizontalPadding)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Constants.Layout.topNavigationBarPadding)
            
            TopAndLeftSideNavigationBar(title: navigationTitle, onSwipeBack: { dismiss() }, leading: {
                Button(action: {
                    if case .save(_, _, let onCancel) = mode { onCancel() }
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: scaled(16), weight: .medium))
                        .frame(width: scaled(20), height: scaled(20))
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                if isEditable {
                    Button("保存") { performSave() }
                        .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    EmptyView()
                }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarHidden(true)
        .onAppear {
            setupFromMode()
        }
        .onDisappear {
            switch mode {
            case .edit(_, _, let onDismiss), .view(_, let onDismiss):
                onDismiss()
            case .save: break
            }
        }
    }
    
    // MARK: - 名称区域
    @ViewBuilder
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名称")
                .font(.headline)
                .foregroundColor(.primary)
            if isEditable {
                TextField("请输入会话名称", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
            } else {
                Text(sessionName.isEmpty ? "—" : sessionName)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            if let id = recordId {
                Text("UID: \(id)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }
    
    // MARK: - 头像区域
    @ViewBuilder
    private var avatarSection: some View {
        let count = avatarImageCount()
        if count > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("头像")
                    .font(.headline)
                    .foregroundColor(.primary)
                if isEditable {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(0..<count, id: \.self) { index in
                                Button(action: { selectedAvatarIndex = index }) {
                                    avatarThumbnail(at: index)
                                        .frame(width: 75, height: 75)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedAvatarIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                                        }
                                        .overlay {
                                            if selectedAvatarIndex == index {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .background(Color.white.clipShape(Circle()))
                                                    .offset(x: 30, y: -30)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .frame(width: 80, height: 80)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                } else {
                    // 查看模式
                    switch mode {
                    case .edit(let record, _, _), .view(let record, _):
                        LoadableSessionAvatarView(sessionId: record.id, fallbackAvatarIndex: selectedAvatarIndex, totalImageCount: count)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .save:
                        EmptyView()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray5))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func avatarThumbnail(at index: Int) -> some View {
        switch mode {
        case .save(let ctx, _, _):
            if index < ctx.images.count {
                Image(uiImage: ctx.images[index])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.gray.opacity(0.2)).overlay { ProgressView() }
            }
        case .edit(let record, _, _), .view(let record, _):
            LoadableSessionImageView(sessionId: record.id, index: index, maxDimension: 150)
                .aspectRatio(contentMode: .fill)
        }
    }
    
    // MARK: - 其它内容区域
    @ViewBuilder
    private var contentSection: some View {
        switch mode {
        case .save(let ctx, _, _):
            saveSummarySection(ctx)
        case .edit(let record, _, _), .view(let record, _):
            recordDetailContent(record: record)
        }
    }
    
    private func saveSummarySection(_ ctx: SaveSessionContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("即将保存")
                .font(.headline)
                .foregroundColor(.primary)
            Text("共 \(ctx.imageCount) 张图片，\(ctx.textLength) 字，保存为会话记录。")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func recordDetailContent(record: SessionRecord) -> some View {
        VStack(spacing: 20) {
            // 基本信息
            VStack(alignment: .leading, spacing: 12) {
                Text("基本信息")
                    .font(.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "创建时间", value: record.formattedCreatedAt)
                InfoRow(label: "更新时间", value: record.formattedUpdatedAt)
                InfoRow(label: "存储大小", value: formatStorageSize(record.storageSize))
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
            
            // 图片预览
            if record.totalImageCount > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("图片预览")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("共 \(record.totalImageCount) 张")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(0..<record.totalImageCount, id: \.self) { index in
                                LoadableSessionImageView(sessionId: record.id, index: index, maxDimension: 400)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 160, height: 300)
                                    .clipped()
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(12)
            }
            
            // 音频信息
            VStack(alignment: .leading, spacing: 12) {
                Text("音频信息")
                    .font(.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "格式", value: record.audioFormat.uppercased())
                InfoRow(label: "时长", value: formatDuration(record.audioDuration))
                InfoRow(label: "大小", value: formatStorageSize(Int64(record.audioSize)))
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
            
            // 处理统计
            VStack(alignment: .leading, spacing: 12) {
                Text("处理统计")
                    .font(.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "OCR耗时", value: "\(Int(record.ocrDuration))秒")
                InfoRow(label: "TTS耗时", value: "\(Int(record.ttsDuration))秒")
                InfoRow(label: "总耗时", value: "\(Int(record.totalDuration))秒")
                InfoRow(label: "有效图片", value: "\(record.validImageCount)/\(record.totalImageCount)张")
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
            
            // 识别文本
            VStack(alignment: .leading, spacing: 12) {
                Text("识别文本")
                    .font(.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "文本长度", value: "\(record.textLength)字符")
                if !record.ocrTextSegments.isEmpty {
                    ForEach(0..<record.ocrTextSegments.count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("图片 \(index + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(record.ocrTextSegments[index])
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    Text(record.ocrText)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
        }
    }
    
    private func avatarImageCount() -> Int {
        switch mode {
        case .save(let ctx, _, _):
            return ctx.images.count
        case .edit(let record, _, _), .view(let record, _):
            return record.totalImageCount
        }
    }
    
    private func setupFromMode() {
        switch mode {
        case .save(let ctx, _, _):
            sessionName = ctx.suggestedName
            selectedAvatarIndex = 0
            if isEditable {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        case .edit(let record, _, _), .view(let record, _):
            sessionName = record.name
            selectedAvatarIndex = record.avatarImageIndex
        }
    }
    
    private func performSave() {
        let name = sessionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let avatarIndex = min(max(0, selectedAvatarIndex), max(0, avatarImageCount() - 1))
        switch mode {
        case .save(_, let onSave, _):
            onSave(name, avatarIndex)
            dismiss()
        case .edit(_, let onSave, _):
            onSave(name, avatarIndex)
            dismiss()
        case .view:
            break
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return m > 0 ? "\(m)分\(s)秒" : "\(s)秒"
    }
    
    private func formatStorageSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - 会话记录详情视图（兼容旧入口，内部使用统一页查看模式）
struct SessionRecordDetailView: View {
    let record: SessionRecord
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        SessionRecordUnifiedView(mode: .view(record, onDismiss: { onDismiss?() }))
    }
}

// MARK: - 信息行视图
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - 按需加载会话头像
struct LoadableSessionAvatarView: View {
    let sessionId: String
    let fallbackAvatarIndex: Int
    let totalImageCount: Int
    @State private var image: UIImage? = nil
    
    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay { ProgressView() }
            }
        }
        .onAppear {
            if image == nil {
                let sid = sessionId
                let fallback = fallbackAvatarIndex
                let total = totalImageCount
                DispatchQueue.global(qos: .userInitiated).async {
                    var loaded = SessionRecordManager.shared.loadAvatar(sessionId: sid)
                    if loaded == nil, total > 0 {
                        let idx = min(max(0, fallback), total - 1)
                        loaded = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: 150)
                            ?? SessionRecordManager.shared.loadImage(sessionId: sid, index: 0, maxDimension: 150)
                    }
                    DispatchQueue.main.async {
                        image = loaded
                    }
                }
            }
        }
        .onDisappear {
            image = nil
        }
    }
}

// MARK: - 按需加载会话图片
struct LoadableSessionImageView: View {
    let sessionId: String
    let index: Int
    var maxDimension: CGFloat? = 400
    @State private var image: UIImage? = nil
    
    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay { ProgressView() }
            }
        }
        .onAppear {
            if image == nil {
                let sid = sessionId
                let idx = index
                let maxD = maxDimension
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: maxD)
                    DispatchQueue.main.async {
                        image = loaded
                    }
                }
            }
        }
        .onDisappear {
            image = nil
        }
    }
}
