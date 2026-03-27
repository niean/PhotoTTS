---
name: scan-dead-code
description: 治理代码时扫描废弃代码
---

# Subskill: 扫描废弃代码

## 任务

扫描源代码查找可能的废弃代码，逐文件读取，输出疑似废弃清单。

## 输入

- {files}：文件路径列表（可选）。未提供时扫描默认范围。

## 默认扫描范围

PhotoTTS/Sources/ 下全部 .swift 文件及 PhotoTTS/Resources/ 下资源文件。

## 检查规则

1. 未使用的类型 -- 已定义但未被其他文件引用的 struct/class/enum/protocol。
2. 未使用的函数 -- 已定义但未被调用的 func（排除 @objc/override/协议实现）。
3. 未使用的变量 -- 已定义但未被读取的 let/var（排除 @Published/@State 等属性包装器）。
4. 未使用的文件 -- 整个文件所有公开符号均未被引用。
5. 无效导入 -- import 的模块在当前文件未使用。
6. 过期注释 -- 注释引用了不存在的类型/函数/文件名。

## 已知排除（不视为废弃）

- @main 标记的 App 入口 struct
- SwiftUI #Preview 宏生成的代码
- Codable 自动合成的 CodingKeys enum
- @objc / @IBAction / @IBOutlet 标记的符号
- 协议要求的方法实现（protocol conformance）
- @ViewBuilder / @resultBuilder 标记的函数
- SwiftUI View 的 body 属性
- extension 中仅提供 static 常量的类型（常量命名空间，如 Constants 子类型）

## 输出格式

```
## 废弃代码 扫描结果
违规数量：N
| # | 文件 | 行号 | 违规项 | 说明 |
|---|------|------|--------|-----|
未发现违规的检查项：...
```
