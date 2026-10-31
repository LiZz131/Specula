---
name: sandtable-replay
description: "用 SandTable 受控执行 Specula 轨迹，并区分适配错误与潜在 bug。Use when: 要在 controlled-execution-runs 下采样回放、记录 failures.tsv，或处理 compare 失败和崩溃。适配层或模型问题修好后新开一轮；潜在 bug 拷贝每条轨迹后继续本轮。"
---

工作流见 `guide.md`。容器和启动见 `references/runtime.md`，采样见 `references/tlc-simulate.md`，判决见 `references/compare-verdict.md`，失败记录见 `references/mismatch-record.md`，轮次报告见 `references/round-report.md`。WRaft 上已经遇到的几类差异见 `examples/wraft.md`。
