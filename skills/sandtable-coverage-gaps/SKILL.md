---
name: sandtable-coverage-gaps
description: "给 SandTable 受控执行里未覆盖的可执行行标 A–E，并决定加轨迹还是交回 Specula。已覆盖的行不分类。崩溃和 sanitizer 报告不进这套分类。Use when: 轮次根上的 lcov.info 和 uncovered.txt 已经写出，要做逐行分类、白名单、调整后覆盖率，或判断未覆盖代码要不要在同一轮次里补 trace。分类文件只在曲线封顶且每条未覆盖行都有下一步时写盘。"
---

工作流见 `guide.md`。集合和顺序见 `references/classification.md`。WRaft 上的标法示例见 `examples/wraft.md`。
