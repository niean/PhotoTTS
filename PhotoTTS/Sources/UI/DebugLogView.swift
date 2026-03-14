import SwiftUI
import os.log

/// 调试日志视图
struct DebugLogView: View {
    @State private var logContent: String = ""
    @State private var isLoading = true
    @State private var showClearConfirmation = false
    @State private var logFileSize: Int64 = 0
    @State private var siriRegisterResult: String? = nil
    
    @Environment(\.dismiss) var dismiss
    
    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack {
            VStack(spacing: 0) {
                Spacer()
                
                // 主内容区
                VStack(spacing: 0) {
                    // Siri 诊断区
                    HStack {
                        Button(action: { registerSiriShortcuts() }) {
                            Label("重新注册 Siri Shortcuts", systemImage: "waveform")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                        
                        if let result = siriRegisterResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("成功") ? .green : .red)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.05))

                    // 日志信息栏
                    HStack {
                        Text("日志大小: \(formatFileSize(logFileSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("最后更新: \(Date().formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    
                    // 日志内容
                    if isLoading {
                        Spacer()
                        ProgressView("加载中...")
                        Spacer()
                    } else if logContent.isEmpty {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("暂无日志")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        // 使用 UITextView 支持选中特定文字、复制到剪切板
                        SelectableLogTextView(text: logContent)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 45) // 为导航栏留出空间
            
            TopAndLeftSideNavigationBar(title: "调试日志", onSwipeBack: { dismiss() }, leading: {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.primary)
                }
            }, trailing: {
                HStack(spacing: 16) {
                    Button(action: { loadLogs() }) {
                        Text("刷新")
                            .font(.system(size: scaled(16), weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    Button(action: { showClearConfirmation = true }) {
                        Text("清空")
                            .font(.system(size: scaled(16), weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            })
        }
        .navigationBarHidden(true) // 隐藏系统导航栏
        .onAppear {
            loadLogs()
        }
        .alert("确认清空", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearLogs()
            }
        } message: {
            Text("确定要清空所有调试日志吗？此操作不可恢复。")
        }
    }
    
    // MARK: - 私有方法
    
    private func loadLogs() {
        isLoading = true
        // 使用 flushAndGetLatestLogs 确保所有待写入日志已落盘后再读取
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 50) { logs, size in
            DispatchQueue.main.async {
                self.logContent = logs
                self.logFileSize = size
                self.isLoading = false
            }
        }
    }
    
    private func clearLogs() {
        DebugLogManager.shared.clearLogs()
        loadLogs()
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func registerSiriShortcuts() {
        siriRegisterResult = "注册中..."
        PhotoTTSShortcuts.updateAppShortcutParameters()
        siriRegisterResult = "注册成功"
        os.Logger.siri.info("App Shortcuts 手动注册成功")
    }
}

// MARK: - 可选文本视图（UITextView 包装）
/// 基于 UITextView 实现，支持选中特定文字、复制到剪切板
/// SwiftUI 的 Text + .textSelection(.enabled) 在 ScrollView 中只能全选，无法选中部分文字
private struct SelectableLogTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.font = UIFont.monospacedSystemFont(ofSize: UIFont.smallSystemFontSize, weight: .regular)
        textView.textColor = UIColor.label
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}

