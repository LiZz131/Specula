---
name: sandtable-coverage
description: "在 SandTable 受控执行上记录行覆盖和分支覆盖。Use when: controlled-execution-runs 里一批 trace 正在或已经回放，需要各配置的 coverage.json，以及轮次根上的并集 lcov.info 和 uncovered.txt。也用于 gcov 计数写不出来或曲线过早变平。sanitizer 轮次的 gcda 不进入这份并集。"
---

工作流见 `guide.md`。进程如何在退出时写计数见 `references/gcov-gotchas.md`，报告长什么样见 `references/report-format.md`。
