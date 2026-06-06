import SwiftUI
import MultipeerConnectivity

struct DeviceTransferView: View {
    /// 要传输的记录 ID 列表（由调用方确定，不为空）
    let sessionIDs: [String]
    var transferMode: TransferMode = .full
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var transferManager = PeerTransferManager.shared

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    private var navigationTitle: String {
        switch transferMode {
        case .full:
            return "传输"
        case .fullWithStats:
            return "传输(带统计)"
        case .playOnly:
            return "传输播放记录"
        }
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
                title: navigationTitle,
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
                // 延迟重启广播，确保设备可被附近设备发现（reset 会停止广播）
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.PeerTransfer.stateResetDelay) {
                    transferManager.startAdvertising()
                }
            }
        }
        .alert("接收传输", isPresented: Binding<Bool>(
            get: { transferManager.pendingInvitation != nil },
            set: { if !$0 { transferManager.pendingInvitation?.handler(false); transferManager.pendingInvitation = nil } }
        )) {
            if let invitation = transferManager.pendingInvitation {
                let allDuplicate = invitation.existingIDs.count == invitation.context.sessionCount
                    && invitation.context.mode.isFullRecordTransfer
                if allDuplicate {
                    Button("确定") {
                        invitation.handler(false)
                        transferManager.pendingInvitation = nil
                    }
                } else if !invitation.storageCheck.isEnough {
                    Button("确定") {
                        transferManager.confirmInsufficientStorageInvitation(invitation)
                    }
                } else {
                    Button("接收") {
                        handleInvitationDecision(invitation: invitation)
                    }
                    Button("拒绝", role: .cancel) {
                        invitation.handler(false)
                        transferManager.pendingInvitation = nil
                    }
                }
            }
        } message: {
            if let invitation = transferManager.pendingInvitation {
                let total = invitation.context.sessionCount
                let existing = invitation.existingIDs.count
                let modeLabel = invitation.context.mode == .playOnly ? "播放" : ""
                if invitation.context.mode.isFullRecordTransfer && existing == total {
                    Text("发送方「\(invitation.context.deviceName)」欲传输 \(total) 条记录，全部已存在无需传输")
                } else if !invitation.storageCheck.isEnough {
                    Text(invitation.storageCheck.message)
                } else if invitation.context.mode.isFullRecordTransfer && existing > 0 {
                    Text("发送方「\(invitation.context.deviceName)」欲传输 \(total) 条记录，其中 \(existing) 条已存在将自动跳过，实际传输 \(total - existing) 条" + (invitation.storageCheck.isAvailableSpaceUnknown ? "\n\(invitation.storageCheck.message)" : ""))
                } else {
                    Text("发送方「\(invitation.context.deviceName)」欲传输 \(total) 条\(modeLabel)记录" + (invitation.storageCheck.isAvailableSpaceUnknown ? "\n\(invitation.storageCheck.message)" : ""))
                }
            }
        }
    }

    private func handleDismiss() {
        transferManager.cancelTransfer()
        dismiss()
    }

    private func handleInvitationDecision(invitation: TransferInvitation) {
        let decision = TransferConflictDecision(
            skipDuplicates: true,
            existingIDs: invitation.existingIDs
        )
        // 存储决策，连接建立后发送给发送方
        transferManager.pendingDecisionToSend = decision
        // 接收方保存本地已存在的 sessionID，供传输完成后使用
        transferManager.setReceiverExistingSessionIDs(invitation.existingIDs)
        // 接受连接
        invitation.handler(true)
        transferManager.pendingInvitation = nil
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
        case .completed(let imported, let skipped):
            completedView(count: imported, skipped: skipped)
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
                        if transferMode == .playOnly {
                            transferManager.invitePeerPlayOnly(peer, sessionIDs: sessionIDs)
                        } else if transferMode == .fullWithStats {
                            transferManager.invitePeerWithStats(peer, sessionIDs: sessionIDs)
                        } else {
                            transferManager.invitePeer(peer, sessionIDs: sessionIDs)
                        }
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

            Text("将传输 \(sessionIDs.count) 条\(transferMode == .playOnly ? "播放" : "")记录")
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
            Text("正在传输 \(transferManager.actualSendCount) 条\(transferMode == .playOnly ? "播放" : "")记录...")
                .font(Constants.Fonts.body)
            if transferManager.skippedDuplicateCount > 0 {
                Text("跳过 \(transferManager.skippedDuplicateCount) 条重复")
                    .font(Constants.Fonts.caption)
                    .foregroundColor(.secondary)
            }
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

    private func completedView(count: Int, skipped: Int) -> some View {
        VStack(spacing: scaled(20)) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(Constants.Fonts.emptyStateIcon)
                .foregroundColor(.green)
            if count == 0 && skipped > 0 {
                Text("无需传输")
                    .font(Constants.Fonts.headline)
                Text("所选 \(skipped) 条记录在对方设备已存在")
                    .font(Constants.Fonts.body)
                    .foregroundColor(.secondary)
            } else {
                Text("传输完成")
                    .font(Constants.Fonts.headline)
                Text("已发送 \(count) 条\(transferMode == .playOnly ? "播放" : "")记录" + (skipped > 0 ? "，跳过 \(skipped) 条已存在" : ""))
                    .font(Constants.Fonts.body)
                    .foregroundColor(.secondary)
            }

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
