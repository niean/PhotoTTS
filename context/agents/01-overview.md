# 项目概览

## 一句话

PhotoTTS（拍照阅读）：iOS 应用，拍照或选图后经 OCR（豆包）与 TTS（火山引擎）转为语音播放，面向 3～10 岁儿童绘本听读与重复收听。

## 技术栈

- 语言与平台：Swift 5.0+，iOS 18.6+
- 架构：MVVM + Coordinator
- UI：SwiftUI 为主，相机等用 UIKit（AVFoundation）
- 网络：URLSession + async/await
- 音频：AVFoundation
- 配置：config_local.json，含 sys、ocr、tts 三节，Bundle 内为默认值；SettingsManager 优先读取 Documents 目录下的同名文件，不存在时回退 Bundle；设置页可编辑并写入 Documents/config_local.json。

## 入口与根状态

- 入口：PhotoTTS/Sources/UI/PhotoTTSApp.swift，@main 为 PhotoTTSApp。
- 初始化：PhotoTTSApp.init() 在主线程同步配置音频会话（AVAudioSession .playback）、初始化 SessionRecordManager 与 DebugLogManager、防息屏（isIdleTimerDisabled = true）。
- 启动页：fullScreenKind 初始值为 .loading，AppLoadingView（Sources/UI/AppPagesView.swift）负责模拟加载进度，约 1.5s 后将 fullScreenKind 置 nil，主界面显现。
- 根状态：AppState（ObservableObject），管理 fullScreenKind（启动页/大图/相机）、selectedTab（底导）、fullScreenCoverImages/Index（全屏大图）、cameraOverlayImages（相机预选）、tab0/2/3ResetId（Tab 刷新触发器）、openCameraOnNextRecordAppear、openPhotoPickerOnNextRecordAppear（首页→制作跨 Tab 标志）、sessionIdToLoadIntoMake（加载已有记录到制作页）、sessionRecordToPlay（Siri 触发播放的待播记录）；竖屏由 AppDelegate 锁定。

## 核心流程

1. 选图：首页或制作 Tab 进入拍照或相册选图（多张）。
2. OCR：ImageToSpeechCoordinator 调用 OCRService（豆包），得到每张图文本并拼接。
3. TTS：同一 Coordinator 调用 NetworkService/TTSService（火山引擎），得到整段音频。
4. 播放：全屏 PlayView 统一播放，支持进度与同步切图。
5. 保存：会话保存为 SessionRecord，由 SessionRecordManager 落盘；record.json 中不存音频数据。

## 文档与规则

操作约束、知识库加载策略见根目录 AGENTS.md。
