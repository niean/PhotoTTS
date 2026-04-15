import SwiftUI

/// 传输接收方公共 UI 组件：邀请确认、进度展示、完成通知、失败通知
/// 用法：.transferReceiver(isActive: condition, onInvitationReceived: { ... })
struct TransferReceiverModifier: ViewModifier {
    /// 当前实例是否展示 UI（false 时全部隐藏，用于入口间互斥）
    let isActive: Bool
    /// 收到邀请或传输开始时的回调（可选），PlayView 用于暂停播放
    var onInvitationReceived: (() -> Void)? = nil

    @ObservedObject private var transferManager = PeerTransferManager.shared

    /// 接受邀请并设置去重决策
    private func acceptInvitation(skipDuplicates: Bool) {
        if let invitation = transferManager.pendingInvitation {
            let decision = TransferConflictDecision(
                skipDuplicates: skipDuplicates,
                existingIDs: invitation.existingIDs
            )
            transferManager.pendingDecisionToSend = decision
            // 接收方保存本地已存在的 sessionID，供传输完成后使用
            transferManager.setReceiverExistingSessionIDs(invitation.existingIDs)
            // 接收方设置去重统计，供进度 overlay 展示
            transferManager.setReceiverDedupInfo(
                totalCount: invitation.context.sessionCount,
                skipDuplicates: skipDuplicates,
                duplicateCount: invitation.existingIDs.count
            )
            invitation.handler(true)
        }
        transferManager.pendingInvitation = nil
    }

    func body(content: Content) -> some View {
        content
            // 邀请到达或传输开始时触发回调
            .onChange(of: transferManager.pendingInvitation?.id) { _, newId in
                if newId != nil { onInvitationReceived?() }
            }
            .onChange(of: transferManager.transferState) { _, newState in
                if newState == .transferring || newState == .importing {
                    onInvitationReceived?()
                }
            }
            // 邀请确认 alert
            .alert(transferManager.receivedTransferMode == .playOnly ? "传输播放记录" : "传输", isPresented: Binding(
                get: { transferManager.pendingInvitation != nil && isActive },
                set: { if !$0 {
                    transferManager.pendingInvitation?.handler(false)
                    transferManager.pendingInvitation = nil
                }}
            )) {
                Button("接收") {
                    acceptInvitation(skipDuplicates: false)
                }
                Button("取消", role: .cancel) {
                    transferManager.pendingInvitation?.handler(false)
                    transferManager.pendingInvitation = nil
                }
            } message: {
                if let invitation = transferManager.pendingInvitation {
                    let total = invitation.context.sessionCount
                    let existing = invitation.existingIDs.count
                    if existing > 0 {
                        Text("\(invitation.context.deviceName) 请求发送 \(total) 条\(invitation.context.mode == .playOnly ? "播放" : "")记录，其中 \(existing) 条已存在（播放记录将覆盖）")
                    } else {
                        Text("\(invitation.context.deviceName) 请求发送 \(total) 条\(invitation.context.mode == .playOnly ? "播放" : "")记录")
                    }
                }
            }
            // 接收进度 overlay
            .overlay {
                if (transferManager.transferState == .transferring || transferManager.transferState == .importing),
                   !transferManager.isSender,
                   isActive {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: Constants.DeviceScale.adaptiveSize(iPhone: 12)) {
                        ProgressView()
                            .tint(.white)
                        if transferManager.transferState == .importing {
                            Text("正在导入 \(transferManager.actualSendCount) 条记录...")
                                .font(Constants.Fonts.headline)
                                .foregroundColor(.white)
                        } else {
                            Text("正在接收 \(transferManager.actualSendCount) 条\(transferManager.receivedTransferMode == .playOnly ? "播放" : "")记录... \(Int(transferManager.transferProgress * 100))%")
                                .font(Constants.Fonts.headline)
                                .foregroundColor(.white)
                        }
                        if transferManager.skippedDuplicateCount > 0 {
                            Text("跳过 \(transferManager.skippedDuplicateCount) 条重复")
                                .font(Constants.Fonts.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Button("取消") {
                            transferManager.cancelTransfer()
                        }
                        .font(Constants.Fonts.body)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            // 接收完成 alert
            .alert("接收完成", isPresented: Binding(
                get: {
                    if case .completed = transferManager.transferState,
                       !transferManager.isSender,
                       isActive {
                        return true
                    }
                    return false
                },
                set: { if !$0 {
                    // 延迟重置并重启广播，确保 MultipeerConnectivity 底层状态完全清理
                    transferManager.reset()
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.PeerTransfer.stateResetDelay) {
                        transferManager.startAdvertising()
                    }
                }}
            )) {
                Button("确定") {}
            } message: {
                if case .completed(let imported, let skipped) = transferManager.transferState {
                    Text("已接收 \(imported) 条\(transferManager.receivedTransferMode == .playOnly ? "播放" : "")记录" + (skipped > 0 ? "，跳过 \(skipped) 条重复" : ""))
                }
            }
            // 接收失败 alert
            .alert("接收失败", isPresented: Binding(
                get: {
                    if case .failed = transferManager.transferState,
                       !transferManager.isSender,
                       isActive {
                        return true
                    }
                    return false
                },
                set: { if !$0 {
                    // 延迟重置并重启广播，确保 MultipeerConnectivity 底层状态完全清理
                    transferManager.reset()
                    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.PeerTransfer.stateResetDelay) {
                        transferManager.startAdvertising()
                    }
                }}
            )) {
                Button("确定") {}
            } message: {
                if case .failed(let msg) = transferManager.transferState {
                    Text(msg)
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// 挂载传输接收方公共 UI（邀请确认、进度、完成、失败）
    /// - Parameters:
    ///   - isActive: 当前实例是否展示 UI（false 时隐藏，用于入口间互斥）
    ///   - onInvitationReceived: 收到邀请或传输开始时的回调（可选）
    func transferReceiver(isActive: Bool, onInvitationReceived: (() -> Void)? = nil) -> some View {
        modifier(TransferReceiverModifier(isActive: isActive, onInvitationReceived: onInvitationReceived))
    }
}
