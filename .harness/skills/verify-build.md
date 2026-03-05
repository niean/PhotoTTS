# Skill: 验证构建

触发：功能迭代完成后自动执行，或人工指令。

步骤：
1. 执行构建，确认零警告零错误：
   ```
   xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTS -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
2. 执行单元测试，确认全部通过：
   ```
   xcodebuild -project PhotoTTS.xcodeproj -scheme PhotoTTSTests -destination 'platform=iOS Simulator,name=iPhone 16' test
   ```
3. 输出验证结果摘要（构建状态、警告数、测试通过/失败数）
