---
name: sandtable-instrumentation
description: "把 Specula 的 TLA+ 规格变成 SandTable 可受控回放的规格。Use when: 已有 spec/base.tla，需要让其中每一个 action 都被控制，包括持久化、崩溃和恢复。系统源码、驱动和 SandTable 源码都放在该次 controlled-execution 目录里：先拷入整份 SandTable，再只改这份副本。也用于同一批轨迹的 AddressSanitizer 与 UndefinedBehaviorSanitizer 构建，泄漏检测关闭。不改 base.tla 的协议公式，不写死某一个系统的 action 或变量名。"
---

工作流见 `guide.md`。`pc` 与 `seq` 见 `references/pc-seq.md`。哪些动作进入 `MCNext`、持久内容怎么判定，见 `references/controllability.md`。配置映射见 `references/config-mapping.md`。本轮目录里放什么，见 `sandtable-workflow-overview.md`。某个系统的命令对照写在 `examples/`，不写进上面这些通用文件。
