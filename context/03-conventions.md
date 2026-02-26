# 约定与约束（实现细节）

本文件是 AGENTS.md「操作约束」的实现级补充，记录具体常量名、函数签名和代码模式。通用规则以 AGENTS.md 为准，此处不重复。

## 页面布局

- 手势：只要顶导左上角支持了返回按钮，就应实现一致的「手势识别」，注释内容为：// 手势识别。
- 手势参数：Constants.Gesture 中有 leftEdgeStartZoneWidth、swipeBackMinTranslation 等，新页面与现有页面保持一致。

## 图片尺寸规则

- 拍摄/选图写入：入队前统一降采样到 `Constants.ImageDisplay.saveImageMaxPixel = 2048px`（像素），通过 `SessionRecordManager.downsampleImageToMaxPixel(_:maxPixelLength:)` 执行。
- 播放/全屏查看：按需从文件加载，最大边长限制 `Constants.ImageDisplay.playbackFullScreenMaxDimension = 1024pt`（点），通过 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)` 执行；预加载相邻页用 `preloadImage`。
- 记录头像：保存时生成，最大边长 `Constants.ImageDisplay.recordAvatarMaxDimension = 96pt`，写入 avatar.jpg。
- 不得绕过降采样直接把原图存入 SessionRecord.imageDataList 或写到磁盘，以免大图撑爆内存。

## OCR 结果处理规则

- `Constants.ocrEmptyResultIndicator = "空字符串"` 是系统保留字符，表示 OCR API 认定该图片没有可识别内容；不是真实文字，不应展示给用户，拼接后需用 `replacingOccurrences` 剔除。
- OCR 失败（网络异常等）时返回空字符串 `""`，与空图片保留位置对应，保持索引与图片一一对应关系，不压缩数组。

## Tab 重置约定

- 离开首页（tab0）、消息（tab2）、我的（tab3）时，`MainTabView` 对应 `tabXResetId` 自增；TabView 内视图通过 `.id(tabXResetId)` 感知变化而销毁重建，清空内部 NavigationStack。
- 制作页（tab1）不参与此重置，因为制作流程有持续状态，不应因 Tab 切换而清空。

## 配置与常量

- 应用级常量与布局、手势、Keychain/UserDefaults 键名集中在 Sources/Constants.swift，新增配置优先在此扩展或使用 config_local.json，避免魔法数字与分散键名。
