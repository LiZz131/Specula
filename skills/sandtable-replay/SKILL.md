---
name: sandtable-replay
description: "用 SandTable 受控执行 Specula 轨迹。base.tla 的每一个 action 都要执行，包括持久化、崩溃和恢复。计划外的进程死亡才记入 failures.tsv 的 crash。Use when: 在 controlled-execution-runs 下采样回放、记录 failures.tsv、处理变量不一致或计划外崩溃，或把已标成 bug 的记录对到上游 issue。计划外 crash 是终态，确认是实现问题后改为 bug 再查上游。bug 通知后继续本轮，adapter 和计划外 crash 停下。超过一条轨迹时放后台，只在失败时通知。"
---

工作流见 `guide.md`。容器和启动见 `references/runtime.md`，采样见 `references/tlc-simulate.md`，判决见 `references/compare-verdict.md`，失败记录见 `references/mismatch-record.md`，轮次报告见 `references/round-report.md`。WRaft 上已经遇到的几类差异见 `examples/wraft.md`。
