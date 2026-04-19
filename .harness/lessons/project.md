<!-- SUMMARY: 项目教训：PhotoTTS开发中踩过的坑和经验，AI自主维护 -->
# 项目教训

AI 自主维护，人工可通过提示或建议触发新增/修正。
项目教训绑定 PhotoTTS，不随 Harness 模板提取。

---

### P001: MultipeerConnectivity 重复传输失败 -- MCSession stale 状态 + SwiftUI alert 互斥

现象：设备间传输记录一次后，再次传输时看不到对方设备，或点击传输后无响应（等待 300s 超时）。

根因：
1. 接收方传输完成后 MCSession 处于 stale 状态（已断连的 peer 仍在 session 中），同一 MCPeerID 再次连接时 MPC 框架可能无法正常建立连接
2. 接收方 "接收完成" alert 阻塞了新到达的邀请 alert（SwiftUI 同一视图多个 .alert 只显示一个），用户关闭完成 alert 时 reset() 清除了新邀请的 pendingInvitation 且未 reject，导致发送方 invitationHandler 永远得不到响应
3. 发送方 DeviceTransferView.onDisappear 中 reset() 停止了广播（advertising）但未重启，设备对其他设备不可见

教训：
- MPC 传输完成/失败后必须 teardown + recreate MCSession，不可复用已断连的 session
- 清除 pendingInvitation 前必须先 reject（调用 handler(false)），否则对端等待超时
- 任何停止 advertising 的路径都必须有对应的重启路径
- SwiftUI 同一视图上多个 .alert 会互相阻塞，接收新邀请时应先清理已完成状态

来源：2026-04-19 传输记录二次传输失败修复
