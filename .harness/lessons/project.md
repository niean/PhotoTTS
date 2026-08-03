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

### P004: 要点媒体进度条依赖要点 TTS 独立分段

现象：播放到要点视频时，视频能作为要点媒体播放，但进度条上没有体现要点页独立位置；早期要点图片场景曾能体现。

根因：
1. PlayView 进度条的可跳转位置来自 `textSegmentRanges`，但实际连续播放和时间显示由 `TTSAudioSegment.duration` 组成的 `PlaybackTimeline` 驱动
2. `ImageToSpeechCoordinator.buildTTSSegments` 会把相邻短文本聚合到同一个 TTS 段
3. 当 LLM 要点文本较短且前一页正文也较短时，末尾要点虚拟页会被合并进前一段，导致要点媒体页没有独立音频段时间点

教训：
- 要点媒体是否为图片或视频不应影响进度条；关键是 `hasVirtualPage` 对应的要点 TTS 必须独立分段
- 排查播放进度问题时，不能只看 PlayView UI；必须同时追踪 Coordinator 输出的 `audioSegments` 和 SessionRecord 持久化结果
- 修改 TTS 聚合策略时，要保留“普通短页可合并”和“要点虚拟页独立”的双重约束，并用单测覆盖

来源：2026-06-13 要点视频未体现在播放进度条修复

### P005: MultipeerConnectivity 无法强制 WiFi-Only，仅蓝牙时"能发现能连但传输失败"

现象：发送方仅有蓝牙（无 Wi-Fi/局域网）时，能发现接收方、能建连、接收方还能判重，但数据传输失败。曾尝试改用 send 分片支持蓝牙，但蓝牙下 send 单条过大触发会话断开、且 send 不阻塞导致发送方进度失真，问题过多，最终放弃蓝牙、改全链路 WiFi-Only。

根因：
1. MCSession.sendResource(at:) 的文件资源传输仅 Wi-Fi 可用；仅蓝牙连接下不可用
2. MCSession.send(_:toPeers:with:) 小消息支持 Wi-Fi 与蓝牙，故发现/建连/邀请信令均能在蓝牙下完成，表现为"能连上但传不动"
3. MultipeerConnectivity 无 transport 控制 API，无法强制"仅 Wi-Fi、禁用蓝牙"，MPC 自动选路（优先 Wi-Fi、蓝牙兜底）

教训：
- MPC 设备间传输不要尝试支持仅蓝牙场景：sendResource 仅 Wi-Fi；send 分片虽支持蓝牙但单条过大断连、不阻塞致进度失真，代价过大
- 要实现"WiFi-Only、不支持蓝牙"，不能用 MPC 的 transport 控制（无此 API），而用 NWPathMonitor 检测 Wi-Fi 可用性作前置门禁：无 Wi-Fi 时不发现/不广播，蓝牙-only 设备被排除在发现阶段之外，失败清晰
- NWPathMonitor 检测 Wi-Fi 接口已关联（availableInterfaces 含 .wifi），局域网即可、不要求互联网；AWDL（Wi-Fi 开但无 LAN）测不到，若需支持无 LAN 点对点要改用 Network framework + Bonjour

来源：2026-08-03 仅蓝牙下设备传输失败、改全链路 WiFi-Only
