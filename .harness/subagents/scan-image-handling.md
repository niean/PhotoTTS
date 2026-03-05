# Subagent: 扫描图片处理规范

## 任务

扫描项目源代码，检查图片处理是否符合规范。逐文件读取并检查，输出违规清单。

## 输入参数

- {files}：需要扫描的文件路径列表（可选）。提供时仅扫描指定文件；未提供时扫描下方"默认扫描范围"中的全部文件。

## 默认扫描范围

读取 /Users/niean/code/github.com/niean/PhotoTTS/PhotoTTS/Sources/ 目录下全部 .swift 文件。

## 检查规则

1. 入队前降采样 -- 图片入队前必须降采样到 2048px（使用 `SessionRecordManager.downsampleImageToMaxPixel`）。不得把原图直接存入 `SessionRecord.imageDataList`。
2. 播放时按需加载 -- 播放时按需加载，最大 1024pt（使用 `SessionRecordManager.loadImage(sessionId:index:maxDimension:)`）。
3. 禁止全尺寸解码再缩放 -- 图片解码必须使用 Image I/O 降采样（CGImageSourceCreateThumbnailAtIndex），禁止先解码全尺寸再缩放，否则 IOSurface 分配失败会导致闪退。
4. 按需加载 + NSCache -- 图片禁止一次性全量加载到内存；播放和浏览必须按需加载当前帧，并通过有限缓存（NSCache）预加载相邻帧。
5. 列表页不加载图片原数据 -- 列表页只读 metadata.json，禁止加载 record.json 或图片原数据。
6. record.json 不存二进制 -- record.json 不存储音频和图片二进制数据，大文件（图片、音频）必须独立存储。
7. 头像预生成缩略图 -- 头像必须在保存时预生成缩略图（avatar.jpg），列表展示时从磁盘加载预生成文件，不得现场从原图生成。
8. 发送到外部 API 的图片降采样 -- 发送到外部 API（OCR/TTS）的图片数据必须经过降采样（2048px），不发送原图，减少数据泄露面。

## 输出格式

```
## 图片处理规范 扫描结果

违规数量：N

| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
| 1 | ... | ... | ... | ... |

未发现违规的检查项：...
```
