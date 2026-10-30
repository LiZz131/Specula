---
name: sandtable-replay
description: "用 SandTable 受控执行 Specula 轨迹，并区分适配错误与潜在 bug。Use when: base_for_sandtable 已经能对单条 trace 发命令，需要随机采样、回放全部建模配置、记录实现侧耗时，或处理 compare 失败。适配层改完后要重跑全部实验。"
---

工作流见 `guide.md`。采样命令见 `references/tlc-simulate.md`，怎样判通过见 `references/compare-verdict.md`，潜在 bug 记什么见 `references/mismatch-record.md`。WRaft 上已经遇到的几类差异见 `examples/wraft.md`。
