# 技术债追踪

| ID | 描述 | 优先级 | 来源计划 | 发现时间 | 状态 |
|----|------|--------|---------|---------|------|
| 5 | 交互优化-缩略图删除按钮(x)尺寸较小，可操作性不足，考虑增大点击区域或长按删除 | low | plan-260317-interaction-analysis | 2026-03-17 | open |
| 9 | 交互优化-OCR结果不展示给用户，无法查看/编辑识别文本，考虑增加预览功能 | medium | plan-260317-interaction-analysis | 2026-03-17 | open |
| 11 | 交互优化-设置页JSON编辑器无语法高亮，缺少配置预设选项 | low | plan-260317-interaction-analysis | 2026-03-17 | open |
| 13 | 交互优化-所有模式下正常状态点击记录行无响应，缺少直觉反馈，建议embedded点击行播放、manage/standard点击行查看详情 | medium | plan-260317-interaction-analysis | 2026-03-17 | open |
| LLM003 | LLMConstants.maxInputTextLength定义在LLMService.swift内部，应迁移到Constants.swift集中管理；provider字符串字面量"doubao"/"openai"在多处硬编码 | low | plan-260319-fix-llm-invocation | 2026-03-19 | open |
| DEBT001 | 架构边界-getAllSessionMetadata/getSessionMetadataPage一次性加载全部metadata.json到内存，无条数上限，大数据量时有内存风险 | medium | plan-250319-playback-direction | 2026-03-19 | open |
| DEBT002 | 编码约定-compressionQuality: 1.0等图片压缩质量值硬编码，应集中到Constants.swift | low | plan-250319-playback-direction | 2026-03-19 | open |
| DEBT003 | 编码约定-文件路径字符串"metadata.json"/"record.json"/"Sessions"等散落在20+处硬编码，应集中定义为常量 | low | plan-250319-playback-direction | 2026-03-19 | open |
| DEBT005 | 图片处理-getImages()使用UIImage(data:)全尺寸解码，未经Image I/O降采样，应标记废弃或改用SessionRecordManager.loadImage | medium | plan-250319-playback-direction | 2026-03-19 | open |
| DEBT006 | 编码约定-PhotoTTSApp.swift第158行`2.0`（Siri启动延迟秒数）硬编码为魔法值，未收归Constants.swift | low | plan-260320-remove-message-tab | 2026-03-20 | open |
| DEBT007 | 图片处理-PlayerImageView第1194行CGImageSourceCreateImageAtIndex fallback全尺寸解码，未经降采样，违反Image I/O规范 | medium | plan-260324-continuous-playback | 2026-03-24 | open |
| DEBT008 | 编码约定-PlayView.swift第746行控制条自动隐藏间隔`1.5`秒硬编码；第937-939/1058-1059行padding数值硬编码，未归入Constants.swift | low | plan-260324-progress-drag-while-playing | 2026-03-24 | resolved |
| DEBT012 | 编码约定-CustomCameraView.swift约30+处UI布局魔法值（圆角/边框/字号/间距等）硬编码，未集中到Constants.swift | low | plan-260329-camera-thumbnail | 2026-03-29 | open |
| DEBT013 | 编码约定-ImageToSpeechProcessingError.errorDescription包含底层error.localizedDescription可能泄露技术细节给用户；缺少technicalDescription属性；ErrorView直接展示error.localizedDescription | medium | plan-260414-manage-load-only | 2026-04-14 | open |
| DEBT014 | 测试债-ReadingReportStats签名变更（continuousDays移除/新增listeningDays等4字段，formattedNear30DaysDuration重命名为formattedNearPeriodDuration）时未同步更新ReadingReportManagerTests；本次为让测试target编译通过已最小化修复（补齐参数、改用新方法名、继承等价断言），但部分测试仅验证格式串未验证语义一致性，需后续审视listeningDays vs 原continuousDays语义对齐 | low | plan-260417-parallel-make-ocr-serial | 2026-04-17 | resolved |
| DEBT015 | 编码约定-SessionRecordManager.swift 既有逻辑会在 Documents/session/export 目录创建 README.txt，与禁止主动创建 README 的项目约定冲突；需评估是否改名或移除说明文件 | low | plan-260606-transfer-storage-precheck | 2026-06-06 | open |

---

## 维护规则

1. **技术债来源**：功能迭代、代码扫描、设计评审等渠道发现的问题
2. **代码扫描问题处理**：代码扫描发现的问题，如非本次变更新引入，应记录到本文件而非要求立即修复
3. **优先级定义**：high-影响核心功能或用户体验，需尽快修复；medium-有替代方案，可排期修复；low-优化项，有空闲时处理
4. **状态流转**：open -> in_progress -> resolved，resolved 状态保留 1 个月后归档
