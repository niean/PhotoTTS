import SwiftUI
import Foundation

// MARK: - JSON语法高亮数据结构
struct JSONToken: Identifiable {
    let id = UUID()
    let text: String
    let type: JSONTokenType
}

enum JSONTokenType {
    case key
    case string
    case number
    case boolean
    case null
    case punctuation
    case whitespace
}

struct JSONLine: Identifiable {
    let id = UUID()
    let tokens: [JSONToken]
}

// MARK: - JSON编辑器视图
struct JSONHighlightView: View {
    @Binding var text: String
    @State private var isEditing = false
    @Binding var isEditingBinding: Bool
    var availableHeight: CGFloat = 600 // 默认高度
    
    private var safeHeight: CGFloat {
        let h = availableHeight
        guard h.isFinite, h > 0 else { return 600 }
        return max(200, h)
    }
    
    var body: some View {
        if isEditing {
            TextEditor(text: $text)
                .font(.system(size: 16, weight: .light, design: .monospaced))
                .padding(12)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .frame(height: safeHeight)
                .onChange(of: isEditingBinding) { _, newValue in
                    if !newValue {
                        isEditing = false
                    }
                }
                .simultaneousGesture(
                    // 允许父视图的点击手势穿透
                    TapGesture()
                        .onEnded { _ in
                            // 空实现，让父视图的手势能够被触发
                        }
                )
        } else {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(parseJSON(text), id: \.id) { line in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(line.tokens, id: \.id) { token in
                                Text(token.text)
                                    .font(.system(size: 16, weight: .light, design: .monospaced))
                                    .foregroundColor(colorForToken(token.type))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minWidth: 800)
            }
            .frame(maxWidth: .infinity, maxHeight: safeHeight)
            .background(Color(.systemGray5))
            .cornerRadius(8)
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        isEditing = true
                        isEditingBinding = true
                    }
            )
        }
    }
    
    private func colorForToken(_ type: JSONTokenType) -> Color {
        switch type {
        case .key:
            return .blue
        case .string:
            return .green
        case .number:
            return .orange
        case .boolean:
            return .purple
        case .null:
            return .gray
        case .punctuation:
            return .primary
        case .whitespace:
            return .primary
        }
    }
    
    private func parseJSON(_ jsonString: String) -> [JSONLine] {
        var lines: [JSONLine] = []
        let jsonLines = jsonString.components(separatedBy: .newlines)
        
        for line in jsonLines {
            var tokens: [JSONToken] = []
            var currentToken = ""
            var inString = false
            var escapeNext = false
            
            for char in line {
                if escapeNext {
                    currentToken.append(char)
                    escapeNext = false
                    continue
                }
                
                if char == "\\" && inString {
                    escapeNext = true
                    currentToken.append(char)
                    continue
                }
                
                if char == "\"" {
                    if inString {
                        // 结束字符串
                        if !currentToken.isEmpty {
                            tokens.append(JSONToken(text: currentToken, type: .string))
                            currentToken = ""
                        }
                        inString = false
                    } else {
                        // 开始字符串
                        if !currentToken.isEmpty {
                            tokens.append(JSONToken(text: currentToken, type: .key))
                            currentToken = ""
                        }
                        inString = true
                    }
                    continue
                }
                
                if !inString {
                    if char.isWhitespace {
                        if !currentToken.isEmpty {
                            tokens.append(JSONToken(text: currentToken, type: determineTokenType(currentToken)))
                            currentToken = ""
                        }
                        tokens.append(JSONToken(text: String(char), type: .whitespace))
                        continue
                    }
                    
                    if "{}[]:,".contains(char) {
                        if !currentToken.isEmpty {
                            tokens.append(JSONToken(text: currentToken, type: determineTokenType(currentToken)))
                            currentToken = ""
                        }
                        tokens.append(JSONToken(text: String(char), type: .punctuation))
                        continue
                    }
                }
                
                currentToken.append(char)
            }
            
            if !currentToken.isEmpty {
                tokens.append(JSONToken(text: currentToken, type: determineTokenType(currentToken)))
            }
            
            lines.append(JSONLine(tokens: tokens))
        }
        
        return lines
    }
    
    private func determineTokenType(_ token: String) -> JSONTokenType {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        
        if trimmed == "true" || trimmed == "false" {
            return .boolean
        } else if trimmed == "null" {
            return .null
        } else if trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            return .number
        } else {
            return .key
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configText: String = ""
    @State private var showingAlert = false
    @State private var isJSONEditing = false
    @State private var alertMessage = ""
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }
    
    private var defaultConfig: String {
        return SettingsManager.shared.loadConfigAsString() ?? SettingsManager.shared.loadDefaultConfig()
    }
    
    var body: some View {
        GeometryReader { geometry in
            CustomZStack {
                VStack(spacing: 0) {
                    // 配置文本区
                    VStack(alignment: .leading, spacing: 12) {
                        JSONHighlightView(
                            text: $configText,
                            isEditingBinding: $isJSONEditing,
                            availableHeight: max(200, geometry.size.height - 45) // 减去顶导，还原/保存已移至顶导右侧
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 55) // 为导航栏留出空间
                    
                    Spacer()
                }
            
                TopAndLeftSideNavigationBar(
                    title: "设置",
                    onSwipeBack: { dismiss() },
                    onLeftAreaTap: { isJSONEditing = false },
                    leading: {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: scaled(16), weight: .medium))
                                .frame(width: scaled(20), height: scaled(20))
                                .foregroundStyle(.primary)
                        }
                    },
                    trailing: {
                        HStack(spacing: scaled(16)) {
                            Button(action: { resetConfig() }) {
                                Text("还原")
                                    .font(.system(size: scaled(16), weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            Button(action: { saveConfig() }) {
                                Text("保存")
                                    .font(.system(size: scaled(16), weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                )
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true) // 隐藏系统导航栏
        .alert("提示", isPresented: $showingAlert) {
            Button("确定") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            loadCurrentConfig()
        }
    }
    
    // 保存配置
    private func saveConfig() {
        // 验证JSON格式
        guard isValidJSON(configText) else {
            alertMessage = "JSON格式不正确，请检查后重试"
            showingAlert = true
            return
        }
        
        // 使用SettingsManager统一保存配置
        if SettingsManager.shared.updateUserConfig(configText) {
            alertMessage = "配置保存成功"
            showingAlert = true
            // 重置编辑状态
            isJSONEditing = false
        } else {
            alertMessage = "保存失败: 无法写入配置文件"
            showingAlert = true
        }
    }
    
    // 还原默认配置
    private func resetConfig() {
        // 使用SettingsManager统一还原配置
        if SettingsManager.shared.resetUserConfigToDefault() {
            // 更新界面显示
            configText = SettingsManager.shared.loadDefaultConfig()
            
            alertMessage = "已还原为默认配置"
            showingAlert = true
            // 重置编辑状态
            isJSONEditing = false
        } else {
            alertMessage = "还原失败: 无法写入配置文件"
            showingAlert = true
        }
    }
    
    // 加载当前配置
    private func loadCurrentConfig() {
        configText = SettingsManager.shared.loadConfigAsString() ?? SettingsManager.shared.loadDefaultConfig()
    }
    
    // 验证JSON格式
    private func isValidJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
    
    
}

#Preview {
    SettingsView()
}
