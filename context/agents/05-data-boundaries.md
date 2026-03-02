# 数据与类型边界

## 会话记录

- SessionRecord（Sources/Models/SessionRecord.swift）：Codable、Identifiable、Hashable。字段包括 id、name、createdAt、updatedAt、imageDataList（Base64）、ocrText、ocrTextSegments、audioDataBase64、audioFormat、audioDuration、ocrDuration、ttsDuration、validImageCount、totalImageCount、textLength、audioSize、voiceSettings、avatarImageIndex、storageSize。与磁盘/JSON 的序列化格式以该模型为准；record.json 中不存储音频数据。

## 语音与配置

- VoiceSettings（Sources/Models/VoiceSettings.swift）：语速、音调等，与 TTS 请求和 SessionRecord 关联。
- 配置：config_local.json 结构见 Resources/config_example.json；SettingsManager 读取并可能被设置页覆盖，Keychain/UserDefaults 键见 Constants.KeychainKeys、Constants.UserDefaultsKeys。

## 协调器输入输出

- ImageToSpeechCoordinator：输入为 [Data]（图片数据）；进度为 ProcessingProgress（stage、currentStep、totalSteps、percentage、message）；完成为 Result<AudioResponse, ImageToSpeechProcessingError>。AudioResponse 与 API 错误类型见 Models/APIResponse.swift 及 Core 中调用处。

## 磁盘存储结构

每条会话记录保存为 `Documents/Sessions/{id}/` 独立目录，结构如下：

```
Documents/Sessions/{id}/
  metadata.json   -- SessionRecordMetadata，用于列表快速加载，不含图片/音频
  record.json     -- SessionRecord 全量字段，但 imageDataList=[] 且 audioDataBase64="" (已剥离)
  images/
    image_0.jpg   -- 第 0 张图（最大边长 2048px 的 JPEG）
    image_1.jpg
    ...
  audio.mp3       -- 独立音频文件（格式由 audioFormat 字段决定）
  avatar.jpg      -- 头像预生成缩略图（最大边长 96pt）
  README.txt      -- 人类可读说明，供"文件"应用查看
```

注意：record.json 编码时故意将 imageDataList 写为 `[]`、audioDataBase64 写为 `""`，图片和音频均以独立文件存储；加载时由 SessionRecordManager.loadSession 从文件重组。避免 record.json 体积过大、占用内存。

## config_local.json 结构

配置文件分三节：

```json
{
  "sys": {
    "ocr_concurrent_count": 8,
    "tts_text_max_length": 10240
  },
  "ocr": {
    "base_url": "",
    "api_key": "",
    "model_name": "",
    "prompt_user": ""
  },
  "tts": {
    "base_url": "",
    "appid": "",
    "access_key": "",
    "cluster": "",
    "uid": "",
    "voice_type": "",
    "encoding": "mp3",
    "speed_ratio": 1.0
  }
}
```

SettingsManager 优先读取 `Documents/config_local.json`，不存在时回退到 Bundle 内的 `config_local.json`；设置页写入的是 Documents 目录版本。

## 导出/导入数据结构

导出包目录结构：

```
PhotoTTS_YYYYMMDD/
  export_manifest.json  -- ExportManifest（含 sessions 列表）
  Sessions/
    {id_1}/             -- 完整会话目录（同磁盘结构）
    {id_2}/
    ...
  README.txt
```

ExportManifest 字段：version、exportDate、appName、totalSessions、totalSize、sessions（ExportSessionInfo 数组）。导入时若 ID 冲突则生成新 UUID，并同步更新 record.json 与 metadata.json 中的 id 字段。

## 边界约定

- UI 层不直接构造或解析 OCR/TTS 的 HTTP 请求与响应体，仅使用 Coordinator 与 Manager 暴露的类型（如 SessionRecord、AudioResponse、ProcessingProgress）。
- 加载列表时只读 metadata.json，不读 record.json，避免大量 IO；完整加载（含音频）只在播放时触发。
- getImages() 方法仅用于兼容旧数据或未保存的 preloadedRecord，新代码应通过 loadImage(sessionId:index:maxDimension:) 按需加载。
