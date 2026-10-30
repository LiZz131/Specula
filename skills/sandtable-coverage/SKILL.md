---
name: sandtable-coverage
description: "在 SandTable 受控执行上记录行覆盖和分支覆盖。Use when: 一批 trace 正在或已经回放，需要覆盖率随条数的曲线、封顶位置、从未执行的代码，以及实现侧耗时。也用于 gcov 计数写不出来或曲线过早变平。"
---

工作流见 `guide.md`。进程如何在退出时写计数见 `references/gcov-gotchas.md`，报告长什么样见 `references/report-format.md`。
