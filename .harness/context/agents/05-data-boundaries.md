# 数据与类型边界

## 会话记录

SessionRecord（Sources/Models/SessionRecord.swift）：Codable、Identifiable、Hashable。字段：id、name、createdAt、updatedAt、imageDataList（Base64）、ocrText、ocrTextSegments、audioDataBase64、audioFormat、audioDuration、ocrDuration、ttsDuration、validImageCount、totalImageCount、textLength、audioSize、voiceSettings、avatarImageIndex、storageSize。record.json 中不存储实际的音频和图片二进制。

## 语音与配置

- VoiceSettings（Sources/Models/VoiceSettings.swift）：speed、pitch、volume、voiceType、encoding，与 TTS 请求和 SessionRecord 关联。
- 配置：config_local.json 结构见 Resources/config_example.json；SettingsManager 读取并可能被设置页覆盖。

## 协调器输入输出

ImageToSpeechCoordinator：输入 [Data]（图片数据）；进度 ProcessingProgress（stage、currentStep、totalSteps、percentage、message）；完成 Result<AudioResponse, ImageToSpeechProcessingError>。

## 磁盘存储结构

```
Documents/Sessions/{id}/
  metadata.json   -- 轻量摘要，用于列表快速加载
  record.json     -- 全量字段，但 imageDataList=[] 且 audioDataBase64=""
  images/
    image_0.jpg   -- JPEG，最大边长 2048px
    image_1.jpg
    ...
  audio.mp3       -- 独立音频文件
  avatar.jpg      -- 头像缩略图，最大 96pt
  README.txt      -- 人类可读说明
```

加载时由 SessionRecordManager.loadSession 从独立文件重组回 SessionRecord 对象。

## config_local.json 结构

```json
{
  "sys": { "ocr_concurrent_count": 8, "tts_text_max_length": 10240 },
  "ocr": { "base_url": "", "api_key": "", "model_name": "", "prompt_user": "" },
  "tts": { "base_url": "", "appid": "", "access_key": "", "cluster": "", "uid": "", "voice_type": "", "encoding": "mp3", "speed_ratio": 1.0 }
}
```

SettingsManager 优先读 Documents/config_local.json，不存在时回退 Bundle 内版本。

## 导出/导入数据结构

```
PhotoTTS_YYYYMMDD/
  export_manifest.json  -- ExportManifest（version、exportDate、appName、totalSessions、totalSize、sessions）
  Sessions/
    {id}/               -- 完整会话目录（同磁盘结构）
  README.txt
```

导入时 ID 重复则跳过。

## 边界约定

- UI 层不直接构造/解析 OCR/TTS HTTP 请求与响应体。
- 列表只读 metadata.json；分页通过 getSessionMetadataPage(offset:limit:)；全量 getAllSessionMetadata() 仅供导出/清空。
- getImages() 仅用于兼容旧数据或未保存的 preloadedRecord，新代码应用 loadImage 按需加载。
