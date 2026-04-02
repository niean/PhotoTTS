<!-- SUMMARY: 数据边界：SessionRecord结构、磁盘存储格式、config_local.json、导入导出格式 -->
# 数据与类型边界

## 会话记录

SessionRecord（PhotoTTS/Sources/Models/SessionRecord.swift）：Codable/Identifiable/Hashable。字段见 ./21-glossary.md。record.json 不存实际音频和图片二进制。

MakeStatus（同文件）：enum { making, completed }，SessionRecord/Metadata 的 makeStatus 均 Optional，nil 表示 completed（向下兼容）。Metadata.isMaking 计算属性供 UI 判断。

AnimationStyle（同文件）：enum { rightToLeft, topToBottom }，SessionRecord/Metadata 的 animationStyle 默认 rightToLeft（横向翻页），向后兼容（旧数据解码时默认横向）。

## 语音与配置

- VoiceSettings（PhotoTTS/Sources/Models/VoiceSettings.swift）：speed/pitch/volume/voiceType/encoding，关联 TTS 请求和 SessionRecord
- config_local.json 结构见下方；SettingsManager 读取，设置页可覆盖

## 协调器输入输出

ImageToSpeechCoordinator：输入 [Data]（图片）；进度 ProcessingProgress（stage/currentStep/totalSteps/percentage/message）；完成 Result<AudioResponse, ImageToSpeechProcessingError>。

## 磁盘存储结构

```
Documents/Sessions/{id}/
  metadata.json   -- 轻量摘要（列表快速加载）
  record.json     -- 全量字段，imageDataList=[] audioDataBase64=""
  history.json    -- 制作/播放历史（SessionHistory），随导入导出
  images/image_0.jpg ... -- JPEG 最大 2048px
  audio.mp3       -- 独立音频
  avatar.jpg      -- 头像缩略图 最大 96pt
  README.txt

Documents/EndPicts/
  h/              -- 横向要点图片（用户上传）
    h-{timestamp}.jpg ...
  z/              -- 纵向要点图片（用户上传）
    z-{timestamp}.jpg ...
```

加载由 SessionRecordManager.loadSession 从文件重组。

用户上传要点图片存储在 Documents/EndPicts/ 目录，与 Bundle 内系统内置图片合并后随机选取。上传时降采样至 2048px，播放时按 1024pt 加载。

## 会话历史（history.json）

SessionHistoryEvent：timestamp(iso8601)/identity(SettingsManager.identityName)。SessionHistory：makeEvents/playEvents。每会话一个 history.json，由 SessionRecordManager 读写（iso8601 日期策略）。导出时随会话目录复制，导入时自动包含。

MakeHistoryManager/PlayHistoryManager 不维护独立文件，委托 SessionRecordManager.addMakeEvent/addPlayEvent 写入会话级 history.json；loadEntries 聚合所有会话生成 UI 条目。

## config_local.json

```json
{
  "sys": { "ocr_concurrent_count": 8, "tts_text_max_length": 10240 },
  "ocr": {
    "provider": "doubao",
    "doubao": { "base_url": "", "model_name": "", "api_key": "" },
    "openai": { "base_url": "", "model_name": "", "api_key": "" }
  },
  "tts": {
    "provider": "huoshan",
    "huoshan": { "base_url": "", "appid": "", "access_key": "" },
    "aliqwen": { "base_url": "", "secret_key": "", "model": "", "voice": "", "language_type": "", "instructions": "", "stream": false }
  },
  "llm": {
    "provider": "doubao",
    "providers": {
      "doubao": { "base_url": "", "model_name": "", "api_key": "", "prompt_user": "", "timeout": 30, "max_retry_count": 3, "retry_delay": 1 },
      "openai": { "base_url": "", "model_name": "", "api_key": "", "prompt_user": "", "timeout": 30, "max_retry_count": 3, "retry_delay": 1 }
    }
  }
}
```

ocr.provider 选择活跃供应商（"doubao"/"openai"），对应子配置独立维护。SettingsManager.getActiveOCRProvider() 读取活跃供应商，loadActiveOCRProviderConfig() 返回对应子配置。API Key 按供应商存储不同 Keychain key（doubao_api_key/openai_ocr_api_key），通过 getOCRAPIKeyForProvider(_:) 获取。

tts.provider 选择活跃供应商（"huoshan"/"aliqwen"），对应子配置独立维护。火山 TTS 音频格式 mp3，阿里千问 TTS 音频格式 wav，SessionRecord.audioFormat 记录实际格式。

llm.provider 选择活跃供应商（"doubao"/"openai"），对应子配置独立维护。SettingsManager.getActiveLLMProvider() 读取活跃供应商，loadActiveLLMProviderConfig() 返回 LLMProviderConfig。API Key 按供应商存储不同 Keychain key（doubao_llm_api_key/openai_llm_api_key），通过 getLLMAPIKeyForProvider(_:) 获取。

SettingsManager 优先读 Documents/config_local.json，不存在时回退 Bundle。

## 导出/导入

```
PhotoTTS_YYYYMMDD/
  export_manifest.json  -- ExportManifest
  Sessions/{id}/        -- 完整会话目录
  README.txt
```

导入时 ID 重复跳过。

## UserDefaults

SettingsManager 通过 UserDefaults 存非敏感配置，键名 Constants.UserDefaultsKeys：identityName（默认设备名，最长 20 字符）、voiceSettings/supportedLanguages/currentLanguage、ttsAppId/ttsCluster/ttsUid、isFirstLaunch/appLaunchCount/lastLaunchDate、maxCacheSize/autoCleanupEnabled。

## 边界约定

- UI 层不直接构造/解析 OCR/TTS HTTP 请求响应
- 列表只读 metadata.json；分页 getSessionMetadataPage(page:pageSize:searchKeyword:caller:) 返回 items+totalCount，pageSize 见 Constants.Pagination；全量 getAllSessionMetadata() 仅供导出/清空/Siri
- getImages() 仅兼容旧数据或 preloadedRecord，新代码用 loadImage 按需加载
