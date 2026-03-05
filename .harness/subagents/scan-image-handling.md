# Subagent: 扫描图片处理规范

## 任务

扫描源代码检查图片处理规范，逐文件读取，输出违规清单。

## 输入

- {files}：文件路径列表（可选）。未提供时扫描默认范围。

## 默认扫描范围

PhotoTTS/Sources/ 下全部 .swift 文件。

## 检查规则

1. 入队前降采样 -- 图片入队降采样 2048px（`downsampleImageToMaxPixel`），不存原图。
2. 播放按需加载 -- 最大 1024pt（`loadImage(sessionId:index:maxDimension:)`）。
3. 禁止全尺寸解码再缩放 -- 必须用 Image I/O CGImageSourceCreateThumbnailAtIndex 直接目标尺寸，禁止先全尺寸再缩。
4. 按需加载 + NSCache -- 禁止全量加载；播放按需加载当前帧 + NSCache 预加载相邻帧。
5. 列表页不加载图片 -- 列表只读 metadata.json，不加载 record.json 或图片。
6. record.json 不存二进制 -- 图片/音频独立文件存储。
7. 头像预生成 -- 保存时生成 avatar.jpg，列表从磁盘加载，不从原图现场生成。
8. 外发图片降采样 -- 发送到外部 API 的图片须经降采样（2048px）。

## 输出格式

```
## 图片处理规范 扫描结果
违规数量：N
| # | 文件 | 行号 | 违规项 | 建议修复 |
|---|------|------|--------|---------|
未发现违规的检查项：...
```
