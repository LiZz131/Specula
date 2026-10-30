---
name: sandtable-instrumentation
description: "把 Specula 的 TLA+ 规格变成 SandTable 可受控回放的规格。Use when: 已有 base.tla 和 MC/hunt 配置，需要加入 pc 与 seq、把 MCNext 限制到驱动能执行的动作，并让 testcase_generator 按 scr.pc 发命令。不改协议语义。"
---

工作流见 `guide.md`。`pc` 与 `seq` 的约定见 `references/pc-seq.md`，哪些动作留在 `MCNext` 里见 `references/controllability.md`，配置怎么映射见 `references/config-mapping.md`。WRaft 上已经对齐过的执行差异见 `examples/wraft.md`。
