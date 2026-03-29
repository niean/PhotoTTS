<!-- SUMMARY: 项目教训：PhotoTTS开发中踩过的坑和经验，AI自主维护 -->
# 项目教训

AI 自主维护，人工可通过提示或建议触发新增/修正。
项目教训绑定 PhotoTTS，不随 Harness 模板提取。

---

### P001: PlayView 防息屏必须在 startPlayback/resumePlayback 中设置

- 现象: 将 PlayView 的 isIdleTimerDisabled 管理移除后依赖全局设置，播放时屏幕熄灭
- 根因: 全局 init() 设置会被系统重置，PlayView 播放启动时必须自行设置 isIdleTimerDisabled = true
- 教训: PlayView 的 startPlayback() 和 resumePlayback() 中必须保留 UIApplication.shared.isIdleTimerDisabled = true，不可删除或外移
- 来源: 2026-03-29, commit 04e20cf
