import SwiftUI
import MultipeerConnectivity

struct DeviceTransferView: View {
    /// 要传输的记录 ID 列表（由调用方确定，不为空）
    let sessionIDs: [String]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var transferManager = PeerTransferManager.shared

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        CustomZStack {
            // 内容区
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, scaled(Constants.Layout.topNavigationBarPadding))
                .background(Color(.systemGroupedBackground))

            // 顶导 + 手势识别
            TopAndLeftSideNavigationBar(
                title: "传输",
                onSwipeBack: { handleDismiss() },
                leading: {
                    Button(action: { handleDismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(Constants.Fonts.navAction)
                            .frame(width: scaled(20), height: scaled(20))
                            .foregroundStyle(.primary)
                    }
                }
            )
        }
        .onAppear {
            transferManager.startBrowsing()
        }
        .navigationBarHidden(true)
        .onDisappear {
            if transferManager.transferState != .transferring {
                transferManager.reset()
            }
        }
    }

    private func handleDismiss() {
        transferManager.cancelTransfer()
        dismiss()
    }

    @ViewBuilder
    private var contentView: some View {
        switch transferManager.transferState {
        case .browsing, .idle, .advertising:
            browsingView
        case .connecting:
            statusView(message: "正在连接...")
        case .preparing:
            statusView(message: "正在打包数据...")
        case .transferring:
            transferringView
        case .completed(let imported, _):
            completedView(count: imported)
        case .failed(let message):
            failedView(message: message)
        case .importing:
            statusView(message: "正在导入...")
        }
    }

    // MARK: - 搜索设备列表

    private var browsingView: some View {
        VStack(spacing: scaled(20)) {
            if transferManager.discoveredPeers.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("正在搜索附近设备...")
                    .font(Constants.Fonts.body)
                    .foregroundColor(.secondary)
                Text("请确认另一台设备已打开 PhotoTTS")
                    .font(Constants.Fonts.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                Spacer()
                List(transferManager.discoveredPeers, id: \.displayName) { peer in
                    Button(action: {
                        transferManager.invitePeer(peer, sessionIDs: sessionIDs)
                    }) {
                        HStack {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(Constants.Fonts.recordActionIcon)
                                .foregroundColor(.blue)
                            Text(peer.displayName)
                                .font(Constants.Fonts.body)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, scaled(8))
                    }
                }
                .listStyle(.insetGrouped)
                Spacer()
            }

            Text("将传输 \(sessionIDs.count) 条记录")
                .font(Constants.Fonts.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, scaled(16))
        }
    }

    // MARK: - 传输进度

    private var transferringView: some View {
        VStack(spacing: scaled(20)) {
            Spacer()
            ProgressView(value: transferManager.transferProgress)
                .progressViewStyle(.linear)
                .frame(width: scaled(200))
            Text("正在传输 \(sessionIDs.count) 条记录...")
                .font(Constants.Fonts.body)
            Text("\(Int(transferManager.transferProgress * 100))%")
                .font(Constants.Fonts.headline)
                .foregroundColor(.blue)

            Button("取消") {
                transferManager.cancelTransfer()
            }
            .font(Constants.Fonts.body)
            .foregroundColor(.red)
            .padding(.top, scaled(10))

            Spacer()
        }
    }

    // MARK: - 完成

    private func completedView(count: Int) -> some View {
        VStack(spacing: scaled(20)) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(Constants.Fonts.emptyStateIcon)
                .foregroundColor(.green)
            Text("传输完成")
                .font(Constants.Fonts.headline)
            Text("已发送 \(count) 条记录")
                .font(Constants.Fonts.body)
                .foregroundColor(.secondary)

            Button("返回") { dismiss() }
                .font(Constants.Fonts.body)
                .foregroundColor(.blue)
                .padding(.top, scaled(10))
            Spacer()
        }
    }

    // MARK: - 失败

    private func failedView(message: String) -> some View {
        VStack(spacing: scaled(20)) {
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .font(Constants.Fonts.emptyStateIcon)
                .foregroundColor(.red)
            Text("传输失败")
                .font(Constants.Fonts.headline)
            Text(message)
                .font(Constants.Fonts.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, scaled(40))

            Button("重试") {
                transferManager.reset()
                transferManager.startBrowsing()
            }
            .font(Constants.Fonts.body)
            .foregroundColor(.blue)
            .padding(.top, scaled(10))

            Button("返回") { dismiss() }
                .font(Constants.Fonts.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - 状态提示

    private func statusView(message: String) -> some View {
        VStack(spacing: scaled(16)) {
            Spacer()
            ProgressView()
            Text(message)
                .font(Constants.Fonts.body)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
