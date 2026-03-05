# Subagent: 扫描安全规范

## 任务

扫描项目源代码，检查是否符合安全规范。逐文件读取并检查，输出违规清单。

## 输入参数

- {files}：需要扫描的文件路径列表（可选）。提供时仅扫描指定文件；未提供时扫描下方"默认扫描范围"中的全部文件。

## 默认扫描范围

- /Users/niean/code/github.com/niean/PhotoTTS/PhotoTTS/Sources/ 目录下全部 .swift 文件
- /Users/niean/code/github.com/niean/PhotoTTS/.gitignore
- /Users/niean/code/github.com/niean/PhotoTTS/PhotoTTS/ 目录下的 Info.plist（如存在）

## 检查规则

1. 密钥只存 Keychain -- API Key、Access Key 等密钥只允许存储在 Keychain（通过 `SettingsManager`），不得硬编码在源码中、不得写入 UserDefaults、不得写入日志。
2. 密钥日志脱敏 -- 日志中禁止输出 API Key、Access Key、Token 等敏感字段；如需标识密钥，仅输出末四位（如 `key=***abcd`）。
3. 配置文件不入库 -- `config_local.json` 已加入 `.gitignore`，包含密钥的配置文件禁止提交到版本库；新增配置文件如含敏感信息，必须同步加入 `.gitignore`。
4. 强制 HTTPS -- 所有外部 API 调用必须使用 HTTPS；不得降级为 HTTP，不得在 Info.plist 中开启 App Transport Security 例外。
5. API 响应校验 -- API 响应必须校验 HTTP 状态码和数据完整性，不信任未经校验的外部输入；JSON 解码失败时按错误处理，不静默忽略。
6. 数据本地存储 -- 用户的绘本图片、音频、会话记录仅存储在设备本地（Documents/Sessions/），不主动上传到任何服务器（OCR/TTS 请求除外）。

## 输出格式

```
## 安全规范 扫描结果

违规数量：N

| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
| 1 | ... | ... | ... | ... |

未发现违规的检查项：...
```
