# Skill: 回填-产品基线更新

触发：人工指令。

步骤：
1. 读取 .harness/context/users/01-prd-specs.md 和 .harness/context/users/01-prd-baseline.md
2. 对比 specs 迭代记录与 baseline，找出 baseline 中缺失或过时的描述
3. 最小化修改 prd-baseline.md，保持既有简洁文风
4. 输出变更摘要（改了哪几处、对应哪个迭代版本）
