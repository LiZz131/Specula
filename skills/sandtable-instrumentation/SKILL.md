---
name: sandtable-instrumentation
description: "把 Specula 的 TLA+ 规格变成 SandTable 可受控回放的规格，并可修改 run 内的源码、驱动和 testcase generator。Use when: 已有 spec/base.tla 和 MC/hunt 配置，需要加入 pc 与 seq、把 MCNext 限制到驱动能执行的动作，或把生成器与驱动放到本次 run 的 sandtable/ 下。也用于为同一批轨迹另开一轮 AddressSanitizer 与 UndefinedBehaviorSanitizer 构建，泄漏检测关闭。不改协议语义，不改 SandTable 仓库。"
---

工作流见 `guide.md`。`pc` 与 `seq` 的约定见 `references/pc-seq.md`，哪些动作留在 `MCNext` 里见 `references/controllability.md`，配置怎么映射见 `references/config-mapping.md`。WRaft 上已经对齐过的执行差异见 `examples/wraft.md`。
