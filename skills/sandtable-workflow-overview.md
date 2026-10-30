# SandTable 受控执行

Specula 套件已经存在之后，用 SandTable 把模型轨迹放到实现上执行。协议公式留在 `spec/base.tla` 和 `spec/MC.tla`。源码、驱动、测试用例生成器的改动写在本次 run 里，不写进 SandTable 仓库。`harness-generation` 打的是 NDJSON；这里打的是控制器命令。

`<run>` 是一次 Specula case study run，例如 `case-studies/systems/willemt-raft/modules/core/runs/case-studies-willemt-raft`。下文路径都相对 `<run>`。

## 四个阶段

```
spec/base.tla、spec/MC.tla、spec/MC.cfg、spec/MC_hunt_*.cfg
artifact/<system>/
        │
        ▼
1. sandtable-instrumentation
   spec/base_for_sandtable.tla、spec/MC_for_sandtable*.tla/cfg
   sandtable/driver/、sandtable/testcase_generator.py
        │
        ▼
2. sandtable-replay
   controlled-execution-runs/<轮次>/<配置>/traces/
        │
        ▼
3. sandtable-coverage
   同轮次各配置的 coverage.json、gcov/，以及 uncovered.txt
        │
        ▼
4. sandtable-coverage-gaps
   未覆盖行标 A–E
        │
        ├─ 下一步是加采样或换常量 → 回到 2，仍在同一轮次，覆盖率往后合并
        └─ 下一步是交回 spec_generation → controlled-execution-runs/<轮次>/scenarios.md
```

采样步数暂时是 30：`DepthBound` 为 `TLCGet("level") < 31`。加长时另用 `spec/MC_for_sandtable_deep.tla`，不改 30 步那份 cfg。

停的条件：这一轮次里每个配置的行覆盖曲线都已封顶，并且合并后每一条未覆盖行都有下一步。封顶指该配置的行覆盖最后一次上升之后不再上升。

同一轮次、同一配置、同一份二进制上再加 trace 时，gcda 保留，`coverage.json` 追加。源码、驱动或生成器改了之后新开一轮次，旧轮次目录留着，不把旧 gcda 并进来。`行分类.tsv` 和 `未覆盖代码分类.md` 只在达到上界的那一次写盘，不保留中间分类。

## 文件位置

| 内容 | 路径 |
|---|---|
| 被测源码 | `artifact/<system>/` |
| 协议规格 | `spec/base.tla`、`spec/MC.tla`、`spec/MC.cfg`、`spec/MC_hunt_*.cfg` |
| 可执行规格 | `spec/base_for_sandtable.tla`、`spec/MC_for_sandtable.tla`、`spec/MC_for_sandtable.cfg`、`spec/MC_for_sandtable_<配置>.cfg` |
| 加长步数 | `spec/MC_for_sandtable_deep.tla`、`spec/MC_for_sandtable_deep.cfg` |
| 驱动 | `sandtable/driver/` |
| 生成器 | `sandtable/testcase_generator.py` |
| 一轮受控执行 | `controlled-execution-runs/<轮次>/` |
| 某配置的轨迹 | `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`、同目录的 `traces.txt`、`log.host` |
| 某配置的曲线 | `controlled-execution-runs/<轮次>/<配置>/coverage.json` |
| 某配置的 gcov | `controlled-execution-runs/<轮次>/<配置>/gcov/*.gcov` |
| 合并后的未覆盖行 | `controlled-execution-runs/<轮次>/uncovered.txt` |
| 逐行分类 | `controlled-execution-runs/<轮次>/行分类.tsv` |
| 分类摘要 | `controlled-execution-runs/<轮次>/未覆盖代码分类.md` |
| 交回 Specula 的场景 | `controlled-execution-runs/<轮次>/scenarios.md` |
| 潜在 bug | `potential-bugs/<短名>/` |

willemt/raft 的 `<system>` 是 `raft`，源码在 `artifact/raft/`。控制器若必须从 SandTable 挂载盘读取，那份是当次执行的工作副本。跑完把轨迹和 gcov 拷回上表的路径。源码、驱动、生成器的修改留在 `<run>` 里。

## 和现有 skill 的边界

| 现有 skill | 关系 |
|---|---|
| `spec_generation` | 仍负责 `spec/base.tla` 和 hunt 配置。E，以及对不上现有动作的 A，退回这里 |
| `harness-generation` | 插桩打 NDJSON，源码也在 `artifact/<system>/`。这里新增的是驱动和生成器 |
| `tla-trace-workflow` | 用实现 trace 校验规格。这里用规格驱动真实进程 |
| `bug-confirmation` | 潜在 bug 记到 `potential-bugs/<短名>/`。确认和修复仍走原来的 bug skill |

## 交接物

| 阶段 | 交给下一阶段的文件 |
|---|---|
| 1 | `spec/base_for_sandtable.tla`、`spec/MC_for_sandtable.tla`、每种建模配置一份 cfg、`sandtable/testcase_generator.py` |
| 2 | `controlled-execution-runs/<轮次>/<配置>/traces/` 下每条轨迹的 `MC.out`、`traces.txt`、`log.host`；`potential-bugs/<短名>/` |
| 3 | 各配置的 `coverage.json` 与 `gcov/`，以及轮次根上的 `uncovered.txt` |
| 4 | `行分类.tsv`、`未覆盖代码分类.md`；继续采样的配置，或 `scenarios.md` |
