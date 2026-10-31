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
        ├─ 潜在 bug → 拷贝每条轨迹到 potential-bugs/，本轮继续
        └─ 适配层或模型 → 写入 failures.tsv，修好后新开一轮次
        ▼
3. sandtable-coverage
   各配置的 coverage.json，以及轮次根上的并集 lcov.info
        │
        ▼
4. sandtable-coverage-gaps
   未覆盖行标 A–E，写入轮次报告
        │
        ├─ 下一步是加采样或换常量 → 回到 2，仍在同一轮次，覆盖率往后合并
        └─ 模型没有这条动作 → scenarios.md，交回 spec_generation
```

一条轨迹怎么从 TLC 进到三个节点，见 `sandtable-replay` 的 `references/runtime.md`。采样步数暂时是 30：`DepthBound` 为 `TLCGet("level") < 31`。加长时另用 `spec/MC_for_sandtable_deep.tla`，不改 30 步那份 cfg。

停的条件：每个配置的行覆盖曲线都已封顶，并集 `lcov.info` 里每一条未覆盖行都有下一步，并且 `failures.tsv` 里每一行都已归类。封顶指该配置的行覆盖最后一次上升之后不再上升。

同一轮次、同一配置、同一份二进制上再加 trace 时，gcda 保留，`coverage.json` 追加。适配层、模型、源码、驱动或生成器改了之后新开一轮次。潜在 bug 不新开一轮。`行分类.tsv`、`未覆盖代码分类.md` 和 `轮次报告.md` 只在达到上界的那一次写盘。报告模板见 `sandtable-replay` 的 `references/round-report.md`。

## 文件位置

| 内容 | 路径 |
|---|---|
| 被测源码 | `artifact/<system>/` |
| 协议规格 | `spec/base.tla`、`spec/MC.tla`、`spec/MC.cfg`、`spec/MC_hunt_*.cfg` |
| 可执行规格 | `spec/base_for_sandtable.tla`、`spec/MC_for_sandtable.tla`、`spec/MC_for_sandtable.cfg`、`spec/MC_for_sandtable_<配置>.cfg` |
| 加长步数 | `spec/MC_for_sandtable_deep.tla`、`spec/MC_for_sandtable_deep.cfg` |
| 驱动 | `sandtable/driver/` |
| 生成器 | `sandtable/testcase_generator.py` |
| 轮次启动脚本 | `sandtable/scripts/run_round.py` |
| 一轮受控执行 | `controlled-execution-runs/<轮次>/` |
| 某配置的轨迹 | `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`、同目录的 `traces.txt`、`log.host` |
| 某配置的曲线 | `controlled-execution-runs/<轮次>/<配置>/coverage.json`、`gcov/*.gcov` |
| 失败 | `controlled-execution-runs/<轮次>/failures.tsv` |
| 并集覆盖率 | `controlled-execution-runs/<轮次>/lcov.info` |
| 未覆盖行 | `controlled-execution-runs/<轮次>/uncovered.txt`，由 lcov 生成 |
| 逐行分类 | `controlled-execution-runs/<轮次>/行分类.tsv` |
| 分类摘要 | `controlled-execution-runs/<轮次>/未覆盖代码分类.md` |
| 给人读的全文 | `controlled-execution-runs/<轮次>/轮次报告.md` |
| 交回 Specula 的场景 | `controlled-execution-runs/<轮次>/scenarios.md` |
| 潜在 bug | `potential-bugs/<短名>/<轨迹>/`，同一类的每一条都拷贝 |

willemt/raft 的 `<system>` 是 `raft`。一次轮次的目录长这样：

```
<run>/artifact/raft/
<run>/sandtable/scripts/run_round.py
<run>/controlled-execution-runs/controlled-execution-1030-1/
  log/traces/t0001/MC.out
  log/coverage.json
  log/gcov/
  failures.tsv
  lcov.info
  uncovered.txt
  行分类.tsv
  未覆盖代码分类.md
  轮次报告.md
  scenarios.md
<run>/potential-bugs/<短名>/t0158/MC.out
```

各配置的百分比各自从零累计。`lcov.info` 的 `SF` 指向 `artifact/raft/`。挂载盘只是容器的工作副本，记录留在这棵树里。

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
| 2 | `traces/` 下每条轨迹的 `MC.out`、`traces.txt`、`log.host`；`failures.tsv`；`potential-bugs/<短名>/<轨迹>/` |
| 3 | 各配置的 `coverage.json` 与 `gcov/`，轮次根上的并集 `lcov.info` 和 `uncovered.txt` |
| 4 | `行分类.tsv`、`未覆盖代码分类.md`、`轮次报告.md`；继续采样的配置，或 `scenarios.md` |
