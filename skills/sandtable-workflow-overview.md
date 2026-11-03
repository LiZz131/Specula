# SandTable 受控执行

Specula 套件已经存在之后，用 SandTable 把模型轨迹放到实现上执行。目标是 `spec/base.tla` 的每一个 action 都被控制，包括持久化、崩溃和恢复。一次受控步是事件循环的一次调用返回。驱动只控制环境：投递、丢失、复制、在时间事件上拨钟、库自己调用的持久化，以及崩溃和恢复。不写库用来做决定的内部字段，不丢弃这次调用已经发出的字节，不在调用内部阻塞来拆步。时间在规格里是事件，不写毫秒。协议公式留在 `spec/base.tla` 和 `spec/MC.tla`。不写死某一个系统的 action 或变量名。持久内容、调用边界和拨钟见 `sandtable-instrumentation` 的 `references/controllability.md`。

每一轮要改的系统源码、驱动和 SandTable 源码都放在该轮目录里。先把 SandTable 整棵源码树拷进来，再只改这份副本。不改上游 SandTable 检出。`harness-generation` 打的是 NDJSON；这里打的是控制器命令。计划外的进程死亡才记失败类 `crash`。

`<run>` 是一次 Specula case study run，例如 `case-studies/systems/<system>/modules/<module>/runs/<run>`。`<ce>` 是其中一轮，`controlled-execution-runs/<轮次>/`。下文没写 `<ce>` 的路径相对 `<run>`。

## 四个阶段

```
<run>/spec/base.tla、MC.tla、MC.cfg、MC_hunt_*.cfg
<ce>/system/、<ce>/sandtable/（本轮的副本）
        │
        ▼
1. sandtable-instrumentation
   <ce>/spec/base_for_sandtable.tla、MC_for_sandtable*.tla/cfg
   <ce>/sandtable/ 里的驱动和 testcase_generator.py
   <ce>/patches/：副本相对基线的补丁
        │
        ▼
2. sandtable-replay
   controlled-execution-runs/<轮次>/<配置>/traces/
        │
        ├─ bug → 库违反协议。拷贝每条轨迹到 potential-bugs/，查上游，本轮继续
        ├─ spec → 停下。把对不上的规格拷进 <ce>/spec/，只对照源码改公式并记 spec-repairs.md，再回到 1 生成适配层，新开一轮回放
        ├─ 计划外 crash → 记下并停。用协议确认后再改为 bug 或 spec
        └─ adapter → 写入 failures.tsv，通知并停，修好后新开一轮次
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

一条轨迹怎么从 TLC 进到模型里的各个节点，见 `sandtable-replay` 的 `references/runtime.md`。节点数等于模型的 server，不默认三个。采样步数暂时是 30：`DepthBound` 为 `TLCGet("level") < 31`。加长时另用 `<ce>/spec/MC_for_sandtable_deep.tla`，不改 30 步那份 cfg。

停的条件：每个配置的行覆盖曲线都已封顶，并集 `lcov.info` 里每一条未覆盖行都有下一步，并且 `failures.tsv` 里每一行都已归类。交出去的那一轮没有 `adapter` 和 `spec`。保持 `crash` 的行算已归类。封顶指该配置的行覆盖最后一次上升之后不再上升。

超过一条轨迹的回放放在后台。正常轨迹不通知。每一条不一致、失败、计划外崩溃、异常退出都通知。受控的崩溃和恢复成功时不通知。续跑跳过已经有判决的轨迹。`bug` 由同一次后台任务继续。`spec`、`adapter` 和计划外 `crash` 停住。`spec` 按 `sandtable-replay` 的 `references/mismatch-record.md`：把对不上的规格拷进 `<ce>/spec/`，只对照 `<ce>/system/` 改公式，记入 `<ce>/spec-repairs.md`，再回到 `sandtable-instrumentation` 生成适配层。`spec` 和 `adapter` 只要修好，就必须新开一轮再采样回放，不能在发现错误的那一轮里接着跑。对齐时不看驱动。变量不一致的归类顺序见同一份 `mismatch-record.md`。模型值不是协议要求的结果。

同一轮次、同一配置、同一份二进制上再加 trace 时，gcda 保留，`coverage.json` 追加。适配层、可执行规格、`<ce>/spec/` 里的协议公式、源码、驱动或生成器改了之后新开一轮次。`bug` 不新开一轮。计划外 `crash` 是终态，可以就是 bug 或 spec：当前 label 不是受控的崩溃时，防御性编码、崩溃或报错把进程打死，记这一类，确认之前不改成 `adapter`、`bug`、`environment` 或 `spec`。确认时用协议语义。确认是实现违反协议后改为 `bug`，再查该仓库的 issue 和 PR。确认是公式把一次符合协议的退出写成了别的状态，改为 `spec`，再走规格对齐。只查已经标成 `bug` 的记录。`行分类.tsv`、`未覆盖代码分类.md` 和 `轮次报告.md` 只在达到上界的那一次写盘。报告模板见 `sandtable-replay` 的 `references/round-report.md`。

`skills/sandtable-instrumentation/examples/` 只读。除非用户明确要求写或改其中某一个文件，不要创建或修改这些例子。

覆盖率轮次之后，可以用同一批 `MC.out` 另开一轮 sanitizer（`-fsanitize=address,undefined`，`ASAN_OPTIONS=detect_leaks=0`）。有报告、且不是受控的崩溃这一步时，记该轮的失败类 `crash`，即使退出码是 0。这份 gcda 不并入覆盖率轮次的 `lcov.info`。

## 文件位置

| 内容 | 路径 |
|---|---|
| 本轮被测源码 | `<ce>/system/` |
| 本轮 SandTable 副本 | `<ce>/sandtable/`。驱动在该系统原来的驱动目录，生成器是 `testcase_generator.py` |
| 副本补丁 | `<ce>/patches/`。生成步骤见 `sandtable-instrumentation` 的 `references/patches.md`。整棵 `<ce>/sandtable` 和 `<ce>/system` 不提交 |
| 协议规格，不改 | `<run>/spec/base.tla`、`MC.tla`、`MC.cfg`、`MC_hunt_*.cfg` |
| 本轮对齐用的协议副本 | `<ce>/spec/base.tla`。出现 `spec` 后从 `<run>/spec/` 拷入再改。下一次插桩用这份，不用 `<run>/spec/base.tla` 覆盖它 |
| 规格修改记录 | `<ce>/spec-repairs.md` |
| 本轮可执行规格 | `<ce>/spec/base_for_sandtable.tla`、`MC_for_sandtable.tla`、`MC_for_sandtable.cfg`、`MC_for_sandtable_<配置>.cfg` |
| 加长步数 | `<ce>/spec/MC_for_sandtable_deep.tla`、`MC_for_sandtable_deep.cfg` |
| 回放循环的一种实现 | `<ce>/sandtable/scripts/run_round.py`。技能不要求这个文件名 |
| 一轮受控执行 | `<ce>`，即 `controlled-execution-runs/<轮次>/` |
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

新的一轮长这样。早先轮次把系统源码放在 `<run>/artifact/`、驱动放在 `<run>/sandtable/`。那些目录不要按新路径去搬。

```
<ce>/system/
<ce>/sandtable/
<ce>/patches/sandtable.patch
<ce>/patches/system.patch
<ce>/spec/base.tla
<ce>/spec/base_for_sandtable.tla
<ce>/spec-repairs.md
<ce>/<配置>/traces/t0001/MC.out
<ce>/<配置>/coverage.json
<ce>/<配置>/gcov/
<ce>/failures.tsv
<ce>/lcov.info
<ce>/uncovered.txt
<ce>/行分类.tsv
<ce>/未覆盖代码分类.md
<ce>/轮次报告.md
<ce>/scenarios.md
<run>/potential-bugs/<短名>/<轨迹>/MC.out
```

各配置的百分比各自从零累计。`lcov.info` 的 `SF` 指向 `<ce>/system/`。挂载盘只是容器的工作副本，记录留在这棵树里。

## 和现有 skill 的边界

| 现有 skill | 关系 |
|---|---|
| `spec_generation` | 仍负责 `spec/base.tla` 和 hunt 配置。E，以及对不上现有动作的 A，退回这里 |
| `harness-generation` | 插桩打 NDJSON，源码在 case study 的 `artifact/<system>/`。本轮另把系统源码拷进 `<ce>/system/`，驱动和生成器在 `<ce>/sandtable/` |
| `tla-trace-workflow` | 用实现 trace 校验规格。这里用规格驱动真实进程 |
| `bug-confirmation` | 潜在 bug 记到 `potential-bugs/<短名>/`。确认和修复仍走原来的 bug skill |

## 交接物

| 阶段 | 交给下一阶段的文件 |
|---|---|
| 1 | `<ce>/spec/` 下的可执行规格和每种建模配置一份 cfg。已有 `<ce>/spec/base.tla` 时用它做协议公式。还有 `<ce>/system/`，`<ce>/sandtable/`（含驱动和生成器），`<ce>/patches/` |
| 2 | `traces/` 下每条轨迹的 `MC.out`、`traces.txt`、`log.host`；`failures.tsv`；`potential-bugs/<短名>/<轨迹>/` |
| 3 | 各配置的 `coverage.json` 与 `gcov/`，轮次根上的并集 `lcov.info` 和 `uncovered.txt` |
| 4 | `行分类.tsv`、`未覆盖代码分类.md`、`轮次报告.md`；继续采样的配置，或 `scenarios.md` |
