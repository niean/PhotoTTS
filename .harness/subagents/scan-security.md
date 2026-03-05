# Subagent: 扫描安全规范

## 任务

扫描源代码检查安全规范，逐文件读取，输出违规清单。

## 输入

- {files}：文件路径列表（可选）。未提供时扫描默认范围。

## 默认扫描范围

PhotoTTS/Sources/ 下全部 .swift、.gitignore、Info.plist（如存在）。

## 检查规则

1. 密钥只存 Keychain -- API Key 等只存 Keychain（SettingsManager），不硬编码、不写 UserDefaults/日志。
2. 密钥日志脱敏 -- 日志禁止输出完整密钥，仅末四位 `key=***abcd`。
3. 配置文件不入库 -- `config_local.json` 在 .gitignore；新增含敏感信息的配置须同步加入。
4. 强制 HTTPS -- 外部 API 全 HTTPS，不降级，不开 ATS 例外。
5. API 响应校验 -- 校验 HTTP 状态码和数据完整性，JSON 解码失败按错误处理。
6. 数据本地存储 -- 用户数据仅存 Documents/Sessions/，不主动上传（OCR/TTS 请求除外）。

## 输出格式

```
## 安全规范 扫描结果
违规数量：N
| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
未发现违规的检查项：...
```
