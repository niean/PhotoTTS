# 项目概览

## 一句话

PhotoTTS（拍照阅读）：iOS 应用，拍照或选图后经 OCR（豆包）与 TTS（火山引擎）转为语音播放，面向 3~10 岁儿童绘本听读。

## 技术栈

- Swift 5.0+，iOS 18.6+
- MVVM + Coordinator
- SwiftUI 为主，相机等用 UIKit（AVFoundation）
- URLSession + async/await
- 音频：AVFoundation
- 配置：config_local.json（sys/ocr/tts 三节），SettingsManager 优先读 Documents 目录，不存在时回退 Bundle；设置页可编辑并写入 Documents/config_local.json

## 入口与根状态

- 入口：PhotoTTSApp.swift，@main 为 PhotoTTSApp
- 初始化：同步配置音频会话（AVAudioSession .playback）、初始化 SessionRecordManager 与 DebugLogManager 单例、防息屏（isIdleTimerDisabled）
- 启动页：fullScreenKind 初始为 .loading，AppLoadingView 模拟约 1.5s 加载后置 nil，主界面显现
- 根状态：AppState（ObservableObject），管理 fullScreenKind、selectedTab、全屏大图数据、相机预选图、tab0/2/3ResetId、跨 Tab 协调标志（openCamera/openPhotoPicker/sessionIdToLoadIntoMake）、sessionRecordToPlay（Siri 触发播放）；竖屏由 AppDelegate 锁定

## 核心流程

1. 选图：首页或制作 Tab 进入拍照或相册选图（多张）
2. OCR：ImageToSpeechCoordinator 调 OCRService（豆包），每张图文本拼接
3. TTS：同一 Coordinator 调 TTSService（火山引擎），得到整段音频
4. 播放：全屏 PlayView 播放，支持进度与同步切图
5. 保存：会话保存为 SessionRecord，由 SessionRecordManager 落盘

## 文档与规则

操作约束、知识库加载策略见根目录 AGENTS.md。
