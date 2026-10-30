---
name: sandtable-coverage-gaps
description: "判断 SandTable 没覆盖到的代码要不要补轨迹。Use when: 覆盖率曲线已经封顶，需要按 spec 变量、防御性分支、守卫谓词、初始化与销毁这四条把未覆盖代码分类；模型能走到的加 trace，模型没建模的写成场景交回 Specula。"
---

工作流见 `guide.md`。四条标准的判定和出路见 `references/classification.md`。WRaft 上已经分过类的函数见 `examples/wraft.md`。
