# Subagent: 扫描架构边界

## 任务

扫描项目源代码，检查是否遵守架构边界约束。逐文件读取并检查，输出违规清单。

## 输入参数

- {files}：需要扫描的文件路径列表（可选）。提供时仅扫描指定文件；未提供时扫描下方"默认扫描范围"中的全部文件。

## 默认扫描范围

- /Users/niean/code/github.com/niean/PhotoTTS/PhotoTTS/Sources/UI/ 目录下全部 .swift 文件
- /Users/niean/code/github.com/niean/PhotoTTS/PhotoTTS/Sources/Core/ 目录下全部 .swift 文件

## 检查规则

1. UI 层不直接调用 OCR/TTS API -- UI 层不直接调用 OCR/TTS API，必须通过 `ImageToSpeechCoordinator` 或 Manager 间接调用。检查 UI/ 目录下的文件是否直接引用 `OCRService` 或 `TTSService`。
2. 全屏页通过 AppState 控制 -- 全屏页面通过 `AppState.fullScreenKind` 控制，不在局部视图用 `fullScreenCover` 绕过（PlayView 例外）。
3. 制作页不参与 Tab 重置 -- 新增 Tab 重置逻辑时，制作页（tab1）不参与重置。
4. 网络请求设超时 -- 网络请求必须设置超时（默认见 `Constants.Network.requestTimeout`，大文件用 `Constants.Network.resourceTimeout`），不允许无限等待。
5. 异步操作非主线程 -- 异步操作（OCR/TTS/文件IO）必须在非主线程执行，回调结果切回主线程更新 UI。
6. 大数据集合设上限 -- 大数据集合（调试日志、历史记录）加载到内存时必须设置条数上限，不允许全量驻留。

## 输出格式

```
## 架构边界 扫描结果

违规数量：N

| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
| 1 | ... | ... | ... | ... |

未发现违规的检查项：...
```
