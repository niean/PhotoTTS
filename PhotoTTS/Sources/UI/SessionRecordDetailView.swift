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
        case edit(SessionRecord, onSave: (String, Int, AnimationStyle) -> Void, onDismiss: () -> Void)
        case view(SessionRecord, onDismiss: () -> Void)
    }
    
    let mode: Mode
    @Environment(\.dismiss) var dismiss
    @State private var sessionName: String = ""
    @State private var sessionNamePrefix: String = ""  // 日期前缀（只读）
    @State private var sessionNameSuffix: String = ""  // 用户可编辑部分
    @State private var selectedAvatarIndex: Int = 0
    @State private var selectedAnimationStyle: AnimationStyle = .rightToLeft
    @State private var showingCoverEdit = false
    @State private var showingAvatarEdit = false
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

    // 日期前缀格式是否有效
    private var isDatePrefixValid: Bool {
        isValidDatePrefix(sessionNamePrefix)
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
                        // 头像选择（仅 save 模式）
                        if case .save = mode {
                            avatarSection
                        }
                        // 头像和封面（edit/view 模式）
                        avatarAndCoverSection
                        // 播放方向
                        animationStyleSection

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
                // 左侧返回按钮（编辑和查看模式统一）
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(Constants.Fonts.navAction)
                        .frame(width: scaled(20), height: scaled(20))
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                if isEditable {
                    // 编辑模式：右侧显示取消、保存两个按钮
                    HStack(spacing: scaled(12)) {
                        Button("取消") {
                            dismiss()
                        }
                        Button("保存") { performSave() }
                            .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty || !isDatePrefixValid)
                    }
                } else {
                    // 查看模式：右侧显示关闭按钮
                    Button("关闭") {
                        dismiss()
                    }
                }
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingCoverEdit) {
            if case .view(let record, _) = mode {
                CoverEditView(sessionId: record.id, editMode: .cover, imageIndex: 0) {
                    showingCoverEdit = false
                }
            } else if case .edit(let record, _, _) = mode {
                CoverEditView(sessionId: record.id, editMode: .cover, imageIndex: 0) {
                    showingCoverEdit = false
                }
            }
        }
        .fullScreenCover(isPresented: $showingAvatarEdit) {
            if case .view(let record, _) = mode {
                CoverEditView(sessionId: record.id, editMode: .avatar, imageIndex: record.avatarImageIndex) {
                    showingAvatarEdit = false
                }
            } else if case .edit(let record, _, _) = mode {
                CoverEditView(sessionId: record.id, editMode: .avatar, imageIndex: selectedAvatarIndex) {
                    showingAvatarEdit = false
                }
            }
        }
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
                .font(Constants.Fonts.headline)
                .foregroundColor(.primary)
            if isEditable {
                // 拆分式名称输入：可编辑日期前缀 + 可编辑后缀
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        // 可编辑的日期前缀（编辑时不含空格，保存时自动补空格）
                        TextField("日期前缀", text: $sessionNamePrefix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: scaled(100))
                            .monospacedDigit()
                            .onChange(of: sessionNamePrefix) { _, newValue in
                                // 限制输入字符：仅允许0-9和英文点号
                                let filtered = newValue.filter { $0.isNumber || $0 == "." }
                                if filtered != newValue {
                                    sessionNamePrefix = filtered
                                    return
                                }
                                // 同步更新 sessionName（前缀 + 后缀，保存时会补空格）
                                sessionName = newValue + " " + sessionNameSuffix
                            }
                        // 可编辑的后缀部分
                        TextField("请输入会话名称", text: $sessionNameSuffix)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextFieldFocused)
                            .onChange(of: sessionNameSuffix) { _, newValue in
                                // 同步更新 sessionName（前缀 + 空格 + 后缀）
                                sessionName = sessionNamePrefix + " " + newValue
                            }
                    }
                    // 日期格式错误提示
                    if !sessionNamePrefix.isEmpty && !isDatePrefixValid {
                        Text("日期格式错误")
                            .font(Constants.Fonts.caption)
                            .foregroundColor(.red)
                    }
                }
            } else {
                Text(sessionName.isEmpty ? "—" : sessionName)
                    .font(Constants.Fonts.body)
                    .foregroundColor(.primary)
            }
            if let id = recordId {
                Text("UID: \(id)")
                    .font(Constants.Fonts.captionMonospaced)
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
                    .font(Constants.Fonts.headline)
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

    // MARK: - 头像和封面区域（edit/view 模式）
    @ViewBuilder
    private var avatarAndCoverSection: some View {
        switch mode {
        case .save:
            EmptyView()
        case .edit(let record, _, _), .view(let record, _):
            if record.totalImageCount > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("头像和封面")
                        .font(Constants.Fonts.headline)
                        .foregroundColor(.primary)

                    HStack(alignment: .top, spacing: 16) {
                        // 左侧：头像（1:1）
                        VStack(spacing: 8) {
                            LoadableSessionAvatarView(
                                sessionId: record.id,
                                fallbackAvatarIndex: selectedAvatarIndex,
                                totalImageCount: record.totalImageCount
                            )
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                if isEditable { showingAvatarEdit = true }
                            }
                            Text("头像")
                                .font(Constants.Fonts.caption)
                                .foregroundColor(.secondary)
                        }

                        // 右侧：封面（16:9）
                        VStack(spacing: 8) {
                            CoverThumbnailView(sessionId: record.id)
                                .frame(height: 80)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(8)
                                .onTapGesture {
                                    if isEditable { showingCoverEdit = true }
                                }
                            Text("封面")
                                .font(Constants.Fonts.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - 播放方向区域
    @ViewBuilder
    private var animationStyleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放方向")
                .font(Constants.Fonts.headline)
                .foregroundColor(.primary)

            if isEditable {
                HStack(spacing: 12) {
                    animationStyleButton(
                        title: "横向",
                        icon: "arrow.left.arrow.right",
                        style: .rightToLeft
                    )
                    animationStyleButton(
                        title: "纵向",
                        icon: "arrow.up.arrow.down",
                        style: .topToBottom
                    )
                }
            } else {
                HStack {
                    Image(systemName: selectedAnimationStyle == .rightToLeft ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                        .foregroundColor(.secondary)
                    Text(selectedAnimationStyle == .rightToLeft ? "横向" : "纵向")
                        .font(Constants.Fonts.body)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray5))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func animationStyleButton(title: String, icon: String, style: AnimationStyle) -> some View {
        Button(action: { selectedAnimationStyle = style }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Constants.Fonts.body)
                Text(title)
                    .font(Constants.Fonts.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedAnimationStyle == style ? Color.blue : Color.clear)
            .foregroundColor(selectedAnimationStyle == style ? .white : .primary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedAnimationStyle == style ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                .font(Constants.Fonts.headline)
                .foregroundColor(.primary)
            Text("共 \(ctx.imageCount) 张图片，\(ctx.textLength) 字，保存为会话记录。")
                .font(Constants.Fonts.subheadline)
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
                    .font(Constants.Fonts.headline)
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
                        .font(Constants.Fonts.headline)
                        .foregroundColor(.primary)
                    Text("共 \(record.totalImageCount) 张")
                        .font(Constants.Fonts.caption)
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
                    .font(Constants.Fonts.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "格式", value: record.audioFormat.uppercased())
                InfoRow(label: "时长", value: formatAudioDuration(record))
                InfoRow(label: "音频段数", value: formatAudioSegmentCount(record))
                InfoRow(label: "大小", value: formatAudioSize(record))
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
            
            // 处理统计
            VStack(alignment: .leading, spacing: 12) {
                Text("处理统计")
                    .font(Constants.Fonts.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "OCR耗时", value: "\(Int(record.ocrDuration))秒")
                if record.llmDuration > 0 {
                    InfoRow(label: "LLM耗时", value: "\(Int(record.llmDuration))秒")
                }
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
                    .font(Constants.Fonts.headline)
                    .foregroundColor(.primary)
                InfoRow(label: "文本长度", value: "\(record.textLength)字符")
                if !record.ocrTextSegments.isEmpty {
                    ForEach(0..<record.ocrTextSegments.count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("图片 \(index + 1)")
                                .font(Constants.Fonts.caption)
                                .foregroundColor(.secondary)
                            Text(record.ocrTextSegments[index])
                                .font(Constants.Fonts.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    Text(record.ocrText)
                        .font(Constants.Fonts.body)
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
            // 解析建议名称：日期前缀 + 后缀
            let suggestedName = ctx.suggestedName
            let (prefix, suffix) = parseSessionName(suggestedName)
            sessionNamePrefix = prefix
            sessionNameSuffix = suffix
            sessionName = suggestedName
            selectedAvatarIndex = 0
            if isEditable {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        case .edit(let record, _, _), .view(let record, _):
            // 解析记录名称：日期前缀 + 后缀
            let recordName = record.name
            let (prefix, suffix) = parseSessionName(recordName)
            sessionNamePrefix = prefix
            sessionNameSuffix = suffix
            sessionName = recordName
            selectedAvatarIndex = record.avatarImageIndex
            selectedAnimationStyle = record.animationStyle
        }
    }
    
    // 解析会话名称：提取日期前缀和自定义后缀
    // 如果名称符合日期前缀格式，返回 (前缀不含空格，后缀)
    // 如果名称不符合格式，返回 (当前日期前缀，原名称)
    // 注意：日期前缀编辑时不带空格，保存时自动补空格
    private func parseSessionName(_ name: String) -> (prefix: String, suffix: String) {
        // 尝试匹配带空格的完整前缀（YY.MM.DD + 空格 = 9字符）
        if name.count >= 9 {
            let prefixWithSpace = String(name.prefix(9))
            // 检查是否符合 YY.MM.DD 格式（第9字符是空格）
            let prefixWithoutSpace = String(prefixWithSpace.prefix(8))
            if isValidDatePrefix(prefixWithoutSpace) && prefixWithSpace.suffix(1) == " " {
                let suffix = String(name.dropFirst(9))
                return (prefixWithoutSpace, suffix)
            }
        }
        // 尝试匹配不带空格的前缀（8字符）
        if name.count >= 8 {
            let prefix = String(name.prefix(8))
            if isValidDatePrefix(prefix) {
                let suffix = String(name.dropFirst(8))
                return (prefix, suffix)
            }
        }
        // 名称不符合日期前缀格式，使用当前日期作为前缀
        let currentDatePrefix = generateDatePrefix()
        return (currentDatePrefix, name)
    }

    // 验证日期前缀格式（yy.MM.dd，不含空格）
    private func isValidDatePrefix(_ prefix: String) -> Bool {
        // 检查格式：2 位数字.2 位数字.2 位数字（共8字符）
        let pattern = #"^\d{2}\.\d{2}\.\d{2}$"#
        return prefix.range(of: pattern, options: .regularExpression) != nil
    }

    // 生成当前日期前缀（不含空格）
    private func generateDatePrefix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: Date())
    }
    
    private func performSave() {
        // 保存时自动补充空格：前缀 + 空格 + 后缀
        let fullPrefix = sessionNamePrefix + " "
        let name = (fullPrefix + sessionNameSuffix).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let avatarIndex = min(max(0, selectedAvatarIndex), max(0, avatarImageCount() - 1))
        switch mode {
        case .save(_, let onSave, _):
            onSave(name, avatarIndex)
            dismiss()
        case .edit(_, let onSave, _):
            onSave(name, avatarIndex, selectedAnimationStyle)
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

    private func formatAudioSegmentCount(_ record: SessionRecord) -> String {
        let segments = record.getAudioSegments()
        return "\(segments.count)段"
    }

    private func formatAudioDuration(_ record: SessionRecord) -> String {
        let segments = record.getAudioSegments()
        if !segments.isEmpty {
            let totalDuration = segments.reduce(0) { $0 + $1.duration }
            if totalDuration > 0 {
                return formatDuration(totalDuration)
            }
        }
        return formatDuration(record.audioDuration)
    }

    private func formatAudioSize(_ record: SessionRecord) -> String {
        let segments = record.getAudioSegments()
        if !segments.isEmpty {
            let totalSize = segments.compactMap(\.audioData).reduce(0) { $0 + $1.count }
            if totalSize > 0 {
                return formatStorageSize(Int64(totalSize))
            }
        }
        return formatStorageSize(Int64(record.audioSize))
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
                .font(Constants.Fonts.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(Constants.Fonts.subheadline)
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
            if image == nil { loadAvatar() }
        }
        .onDisappear {
            image = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.avatarImageDidUpdate)) { notification in
            if let updatedId = notification.userInfo?["sessionId"] as? String, updatedId == sessionId {
                loadAvatar()
            }
        }
    }

    private func loadAvatar() {
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

// MARK: - 封面缩略图视图
struct CoverThumbnailView: View {
    let sessionId: String
    @State private var coverImage: UIImage?

    private var maxDimension: CGFloat {
        Constants.HomeCard.coverAvatarMaxDimension
    }

    var body: some View {
        Group {
            if let image = coverImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // 占位图
                Rectangle()
                    .fill(Color(.systemGray4))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(Constants.Fonts.homeCardPlaceholderIcon)
                                .foregroundColor(.gray)
                            Text("暂无封面")
                                .font(Constants.Fonts.caption)
                                .foregroundColor(.gray)
                        }
                    )
            }
        }
        .onAppear { loadCoverImage() }
        .onReceive(NotificationCenter.default.publisher(for: Constants.NotificationNames.coverImageDidUpdate)) { notification in
            if let updatedId = notification.userInfo?["sessionId"] as? String, updatedId == sessionId {
                loadCoverImage()
            }
        }
    }

    private func loadCoverImage() {
        DispatchQueue.global(qos: .utility).async {
            // 优先加载封面图
            var image = SessionRecordManager.shared.loadCoverImage(sessionId: sessionId, maxDimension: maxDimension)
            // 封面不存在时降级使用第一张图
            if image == nil {
                image = SessionRecordManager.shared.loadFirstImageAsCover(sessionId: sessionId, maxDimension: maxDimension)
            }
            DispatchQueue.main.async {
                coverImage = image
            }
        }
    }
}
