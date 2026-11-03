---
name: sandtable-instrumentation
description: "把 Specula 的 TLA+ 规格变成 SandTable 可受控回放的规格。Use when: 已有 spec/base.tla，需要让其中每一个 action 都被控制，包括持久化、崩溃和恢复。一次受控步是事件循环的一次调用返回。驱动只控制环境：投递、丢失、复制、在时间事件上拨钟、库自己调用的持久化、崩溃和恢复。不写库用来做决定的内部字段，不丢弃本次调用已经发出的字节，不在调用内部阻塞来拆分 action。时间是事件，不写毫秒。系统源码、驱动和 SandTable 源码都放在该次 controlled-execution 目录里：先拷入整份 SandTable，再只改这份副本，并把副本相对基线的差异写成 patches。也用于同一批轨迹的 AddressSanitizer 与 UndefinedBehaviorSanitizer 构建，泄漏检测关闭。不改 base.tla 的协议公式，不写死某一个系统的 action 或变量名。"
---

工作流见 `guide.md`。`pc` 与 `seq` 见 `references/pc-seq.md`。哪些动作进入 `MCNext`、持久内容怎么判定，见 `references/controllability.md`。配置映射见 `references/config-mapping.md`。副本相对基线的补丁见 `references/patches.md`。本轮目录里放什么，见 `sandtable-workflow-overview.md`。某个系统的命令对照如果已经在 `examples/`，只读，不写进上面这些通用文件。

`examples/` 下的文件不要创建、修改或覆盖，除非用户在对话里明确要求写或改其中某一个文件。回放、插桩、修规格、补命令对照，都不构成这种要求。系统相关的命令写在本轮目录，不写进 `examples/`。
