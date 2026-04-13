<!-- SUMMARY: 项目概览：iOS绘本听读应用，技术栈Swift/iOS18.1+/MVVM+SwiftUI，核心流程制作(OCR+LLM+TTS)-保存-播放 -->
# 项目概览

## 一句话

PhotoTTS（拍照阅读）：iOS 应用，拍照/选图经 OCR（多 Provider：豆包/OpenAI）、LLM（多 Provider：豆包/OpenAI）与 TTS（多 Provider：火山引擎/阿里千问）转语音播放，面向 3~10 岁儿童绘本听读。

## 技术栈

Swift 5.0+，iOS 18.1+，MVVM+Coordinator，SwiftUI 为主（相机用 UIKit/AVFoundation），URLSession+async/await，音频 AVFoundation。配置：运行时配置文件为沙箱 Documents 目录中的 config_local.json（sys/ocr/tts/llm 四节），首次由 Bundle 的 `PhotoTTS/Resources/config_example.json` 初始化；SettingsManager 优先读该文件，不存在时回退 Bundle，设置页可直接编辑。

## 入口与根状态

- 入口：PhotoTTSApp.swift（@main），初始化：异步配置音频会话（.playback 后台线程）、初始化 SessionRecordManager/DebugLogManager 单例、防息屏
- 启动页：fullScreenKind 初始 .loading，AppLoadingView 约 1.5s 后置 nil
- 根状态：AppState（ObservableObject）管理 fullScreenKind、selectedTab、全屏大图/相机数据、tabXResetId（tab0/2/3）、跨 Tab 协调标志（openCameraOnNextRecordAppear/openPhotoPickerOnNextRecordAppear/sessionIdToLoadIntoMake）、sessionRecordToPlay（Siri）、isPlayViewActive（播放互斥）、makeTaskIdToReconnect、recordIdToEditInManageTab、loadingProgress/loadingMessage；竖屏 AppDelegate 锁定

## 核心流程

1. 制作：制作 Tab 拍照/相册多选，经 OCR（多 Provider：豆包/OpenAI）、LLM（多 Provider：豆包/OpenAI）、TTS（多 Provider：火山引擎/阿里千问）完成制作
2. 保存：SessionRecord 由 SessionRecordManager 落盘，解耦记录生产和使用
3. 播放：从首页选择已保存记录，全屏 PlayView 播放，支持进度同步切图

## 文档与规则

操作约束见 `.harness/framework/FRAMEWORK.md`，知识库加载策略见 `.harness/PROJECT.md`。
