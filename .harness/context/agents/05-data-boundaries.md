# 数据与类型边界

## 会话记录

SessionRecord（Sources/Models/SessionRecord.swift）：Codable、Identifiable、Hashable。字段：id、name、createdAt、updatedAt、imageDataList（Base64）、ocrText、ocrTextSegments、audioDataBase64、audioFormat、audioDuration、ocrDuration、ttsDuration、validImageCount、totalImageCount、textLength、audioSize、voiceSettings、avatarImageIndex、storageSize、makeStatus。record.json 中不存储实际的音频和图片二进制。

MakeStatus（Sources/Models/SessionRecord.swift）：enum MakeStatus: String, Codable { case making; case completed }。SessionRecord.makeStatus 和 SessionRecordMetadata.makeStatus 均为 Optional，nil 表示 completed（向下兼容旧数据）。SessionRecordMetadata.isMaking 计算属性便于 UI 判断。

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
  history.json    -- 该会话的制作/播放历史事件（SessionHistory），随会话导入导出
  images/
    image_0.jpg   -- JPEG，最大边长 2048px
    image_1.jpg
    ...
  audio.mp3       -- 独立音频文件
  avatar.jpg      -- 头像缩略图，最大 96pt
  README.txt      -- 人类可读说明
```

加载时由 SessionRecordManager.loadSession 从独立文件重组回 SessionRecord 对象。

## 会话历史（history.json）

SessionHistoryEvent（Sources/Models/SessionRecord.swift）：timestamp（Date, iso8601）、identity（String, 发起者身份来自 SettingsManager.identityName）。

SessionHistory（Sources/Models/SessionRecord.swift）：makeEvents: [SessionHistoryEvent]、playEvents: [SessionHistoryEvent]。每个会话目录下一个 history.json，由 SessionRecordManager 读写（historyEncoder/historyDecoder 使用 iso8601 日期策略）。导出时随会话目录整体复制，导入时自动包含。

MakeHistoryManager / PlayHistoryManager 不再维护独立 JSON 文件，recordSave / recordPlay 委托 SessionRecordManager.addMakeEvent / addPlayEvent 写入会话级 history.json；loadEntries 聚合所有会话的 history.json 生成 UI 展示条目。

旧数据迁移：启动时 SessionRecordManager.migrateHistoryToSessionsIfNeeded() 一次性将 Documents/make_history.json 和 play_history.json 按会话名称匹配写入对应 history.json（UserDefaults flag: didMigrateHistoryToSessions），旧文件保留不删除。

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

## UserDefaults 存储

SettingsManager 通过 UserDefaults 存储非敏感用户配置，键名定义在 Constants.UserDefaultsKeys：
- identityName: 用户身份名称，默认取 UIDevice.current.name（iOS 16+ 返回 "iPhone" 等通用名），最长 20 字符，空值回退设备名称
- voiceSettings / supportedLanguages / currentLanguage: 语音与语言配置
- ttsAppId / ttsCluster / ttsUid: TTS 非敏感参数
- isFirstLaunch / appLaunchCount / lastLaunchDate: 启动统计
- maxCacheSize / autoCleanupEnabled: 缓存策略

## 边界约定

- UI 层不直接构造/解析 OCR/TTS HTTP 请求与响应体。
- 列表只读 metadata.json；分页通过 getSessionMetadataPage(offset:limit:)；全量 getAllSessionMetadata() 仅供导出/清空。
- getImages() 仅用于兼容旧数据或未保存的 preloadedRecord，新代码应用 loadImage 按需加载。
