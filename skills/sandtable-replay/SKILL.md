---
name: sandtable-replay
description: "用 SandTable 受控执行 Specula 轨迹，并区分适配错误与潜在 bug。Use when: spec/base_for_sandtable.tla 已经能对单条 trace 发命令，需要在 controlled-execution-runs/<轮次>/ 下采样、回放全部建模配置、记录实现侧耗时，或处理 compare 失败。源码、驱动或生成器改完后新开一轮次。"
---

工作流见 `guide.md`。采样命令见 `references/tlc-simulate.md`，怎样判通过见 `references/compare-verdict.md`，潜在 bug 记什么见 `references/mismatch-record.md`。WRaft 上已经遇到的几类差异见 `examples/wraft.md`。
