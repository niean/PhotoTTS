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

### P002: 设备传输判重不能依赖短时 metadata 缓存

现象：发送方再次制作后沿用原 session ID，接收方即使已经删除旧记录，重新传输时仍可能被判定为“ID 重复”并直接跳过。

根因：
1. `SessionRecordManager.getAllSessionMetadata()` 有 2 秒短时缓存，适合首页等读多写少场景
2. `PeerTransferManager` 邀请阶段的重复检查，以及导入阶段的 ID 判重，直接复用了这层缓存
3. 当本地删除刚发生、磁盘已变化但缓存尚未刷新时，传输链路会把已删除记录误判成仍然存在

教训：
- 任何“删除后立即判重”的传输/导入路径，都必须强制刷盘读取 metadata，不能复用短时缓存
- 短时缓存只适用于展示和普通查询；影响导入/覆盖/去重决策的路径，必须优先保证一致性

来源：2026-05-01 再次制作后设备传输误判重复修复

### P003: 导出快照的完整性清单必须基于目标快照文件

现象：再次制作后的记录在发送端本地可正常使用，但传输到接收方后会被判定为“完整性校验失败”。

根因：
1. 导出快照时，文件是先从源目录复制到导出目录
2. 旧实现生成 `integrity.json` 时，对多数文件使用的是“源目录文件”的 MD5/size，而不是“导出目录里的实际快照文件”
3. 一旦导出过程中源目录文件发生回写，哪怕用户是在再次制作完成很久以后才发起传输，导出包里的文件和完整性清单仍可能不一致

教训：
- `integrity.json` 的职责是描述“导出快照本身”，因此 MD5/size 必须全部从目标快照文件读取
- 任何快照/归档/备份流程，只要存在“先复制、后校验”的步骤，校验源都必须指向复制结果，不能混用在线源文件

来源：2026-05-01 再次制作记录传输完整性校验失败修复
