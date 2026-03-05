# Subagent: 扫描架构边界

## 任务

扫描源代码检查架构边界约束，逐文件读取，输出违规清单。

## 输入

- {files}：文件路径列表（可选）。未提供时扫描默认范围。

## 默认扫描范围

PhotoTTS/Sources/UI/ 和 PhotoTTS/Sources/Core/ 下全部 .swift 文件。

## 检查规则

1. UI 不直接调 OCR/TTS -- UI/ 下不直接引用 `OCRService`/`TTSService`，须通过 Coordinator 或 Manager。
2. 全屏页通过 AppState 控制 -- 全屏页用 `AppState.fullScreenKind`，不在局部视图用 `fullScreenCover`（PlayView 例外）。
3. 制作页不参与 Tab 重置 -- tab1 不参与 tabResetId 重置。
4. 网络请求设超时 -- 必须设超时（`Constants.Network.requestTimeout`/`resourceTimeout`），不允许无超时。
5. 异步操作非主线程 -- OCR/TTS/文件IO 后台执行，回调切回主线程更新 UI。
6. 大数据集合设上限 -- 调试日志、历史记录等加载到内存必须设条数上限。

## 输出格式

```
## 架构边界 扫描结果
违规数量：N
| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
未发现违规的检查项：...
```
