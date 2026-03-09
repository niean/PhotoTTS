# PhotoTTS - 拍照阅读

<div align="center">
  <img src="PhotoTTS/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" alt="PhotoTTS Logo" width="120" height="120">
  
  <h3>拍照阅读，让绘本更精彩</h3>
  
  [![iOS](https://img.shields.io/badge/iOS-18.6+-blue.svg)](https://developer.apple.com/ios/)
  [![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
</div>

## 项目简介

PhotoTTS 是一款面向 3-10 岁儿童的绘本听读 iOS 应用。拍照或选择相册图片，自动识别文字并合成语音，让孩子随时重复收听喜欢的绘本故事。

## 核心特性

- 拍照识别：支持拍照和相册选图（多张），支持对已有记录重新制作
- 文字识别：支持豆包大模型、OpenAI 等多种 OCR 服务
- 语音合成：支持火山引擎、阿里通义千问等多种 TTS 服务
- 绘本播放：音频播放联动图片与文字，支持全屏播放器
- 会话记录：保存记录以便重复收听，支持导出导入备份

## 主要功能

- 拍照阅读：拍照/选图 → OCR识别 → TTS合成 → 绘本播放

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

3. 配置 API 密钥
   ```bash
   cp PhotoTTS/Resources/config_example.json PhotoTTS/Resources/config_local.json
   ```
   编辑 `config_local.json`，填入您的 API 密钥（支持配置多种 OCR/TTS 服务商）

4. 构建运行
   - 选择目标设备或模拟器
   - 按 Cmd + R 构建并运行

## 项目结构

```
PhotoTTS/
├── Sources/
│   ├── Core/
│   │   ├── Coordinators/    # 业务编排
│   │   ├── Handlers/        # OCR / TTS 服务
│   │   ├── Intents/         # Siri Intents
│   │   └── Managers/        # 会话、设置、历史、后台制作等
│   ├── Models/              # 数据模型
│   └── UI/                  # SwiftUI 视图
├── Resources/
│   └── config_local.json    # API 密钥配置（不入库）
└── Assets.xcassets/
```

## 技术规格

- 开发语言：Swift 5.0+
- 最低支持版本：iOS 18.6+
- 架构模式：MVVM + Coordinator
- UI框架：SwiftUI
- 网络框架：URLSession + async/await
- 音频框架：AVFoundation

## 致谢

感谢以下服务提供商：

- [豆包模型](https://www.doubao.com/) - OCR 文字识别服务
- [火山引擎](https://www.volcengine.com/) - TTS 语音合成服务
- [阿里通义](https://tongyi.aliyun.com/) - TTS 语音合成服务

---

<div align="center">
  <p>拍照阅读，让绘本更精彩</p>
</div>
