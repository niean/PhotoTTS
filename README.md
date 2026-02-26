# PhotoTTS - 拍照阅读

<div align="center">
  <img src="PhotoTTS/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" alt="PhotoTTS Logo" width="120" height="120">
  
  <h3>拍照阅读，让绘本更精彩</h3>
  
  [![iOS](https://img.shields.io/badge/iOS-18.6+-blue.svg)](https://developer.apple.com/ios/)
  [![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
</div>

## 项目简介

PhotoTTS 是一款智能拍照文字转语音iOS应用。通过拍照或选择相册图片，应用能够自动识别图片中的文字内容，并将其转换为自然流畅的语音，提供
便捷的阅读体验。

### 目标用户

专为3-10岁儿童设计，帮助儿童阅读纸质绘本、重复收听。

## 核心特性

- 拍照识别：支持拍照和相册选择图片
- 文字识别：基于豆包大模型OCR API的高精度文字识别
- 语音合成：调用火山引擎TTS API生成自然语音
- 音频播放：完整的播放控制（播放、暂停、进度控制）
- 会话记录：支持保存会话记录，以便重复收听音频、备份数据

## 主要功能

- 拍照阅读：拍照或选择图片(多张) → OCR识别 → TTS合成 → 音频播放

## 快速开始

### 环境要求

- iOS 18.6+
- macOS 12.0+
- Xcode 15.0+

### 安装步骤

1. 克隆项目
   ```
   git clone https://github.com/niean/PhotoTTS.git
   cd PhotoTTS
   ```

2. 打开项目
   ```
   open PhotoTTS.xcodeproj
   ```

3. 配置API密钥
   - 复制 `PhotoTTS/Resources/config_example.json` 为 `config_local.json`
   - 在 `config_local.json` 中配置您的API密钥

4. 构建运行
   - 选择目标设备或模拟器
   - 按 Cmd + R 构建并运行

### API配置

在 `PhotoTTS/Resources/config_local.json` 中配置API密钥：

1. 复制示例配置文件：
   ```bash
   cp PhotoTTS/Resources/config_example.json PhotoTTS/Resources/config_local.json
   ```

2. 编辑 `config_local.json`，填入您的 API 密钥


## 项目结构

```
PhotoTTS/
├── Sources/
│   ├── Core/
│   │   ├── Coordinators/
│   │   ├── Handlers/
│   │   └── Managers/
│   ├── Models/
│   └── UI/
├── Resources/
│   └── config_local.json
└── doc/
```

## 技术规格

- 开发语言：Swift 5.0+
- 最低支持版本：iOS 18.6+
- 架构模式：MVVM + Coordinator
- UI框架：SwiftUI + UIKit混合使用
- 网络框架：URLSession + async/await
- 音频框架：AVFoundation


## 致谢

感谢以下服务提供商：

- [豆包模型](https://www.doubao.com/) - OCR文字识别服务
- [火山引擎](https://www.volcengine.com/) - TTS语音合成服务

---

<div align="center">
  <p>拍照阅读，让绘本更精彩</p>
</div>
