# 覆盖率缺口

`sandtable-coverage` 写出 `uncovered.txt` 之后，只给未覆盖的可执行行一个集合，再决定加轨迹还是交回 Specula。次数大于 0 的行不分类。不改 `spec/base.tla` 的协议公式。判定见 `references/classification.md`。路径相对 `<run>`，定义见 `sandtable-workflow-overview.md`。

计划外的崩溃、异常退出和 sanitizer 报告不在 A–E 里，记在该轮次的 `failures.tsv`。受控的崩溃和恢复不是这种失败。防御性行仍按本技能分类。进程被 assert 打死时，判决归 `sandtable-replay`，用协议语义区分 `bug` 和 `spec`，不用模型值当目标。

## 输入 / 输出

**输入**：

- `controlled-execution-runs/<轮次>/lcov.info`，以及由它生成的 `uncovered.txt`
- `spec/base_for_sandtable.tla`、`spec/MC_for_sandtable*.tla`、对应 cfg 里的常量
- `spec/base.tla` 里的变量

**输出**，只在这一轮次达到上界时写盘。循环中途不留上一份分类。

- `controlled-execution-runs/<轮次>/行分类.tsv`：`uncovered.txt` 里每一行一条。列是 `文件`、`行号`、`集合`、`依据`、`下一步`。集合只写 A、B、C、D、E。
- `controlled-execution-runs/<轮次>/未覆盖代码分类.md`：按集合写行数、原始覆盖率、调整后覆盖率、每个集合的下一步。不逐行复述。
- `controlled-execution-runs/<轮次>/scenarios.md`：E，以及对不上现有动作的 A。交给 `spec_generation`。

## 步骤

1. 确认 dump 有效。`sandtable-coverage` 的 `references/gcov-gotchas.md` 描述了计数被冻住时的样子。`#####` 才是未执行。
2. 按 `references/classification.md` 的顺序给 `uncovered.txt` 的每一行分类。一行只进一个集合。
3. 下一步是加采样或换常量的 A 和 B，回到 `sandtable-replay`，仍用这一轮次。`sandtable-coverage` 把新 trace 合并进原配置的 `coverage.json` 和 `gcov/`，并重写并集 `lcov.info` 和 `uncovered.txt`。次数变成大于 0 的行从新的 `uncovered.txt` 里消失。
4. 新轨迹仍走 `sandtable-replay` 的判决。改了 `Sand*`、源码、驱动或生成器之后新开一轮次，不把旧 gcda 并进来。
5. E，以及对不上现有动作的 A，写入 `scenarios.md`。C 和 D 不采样。

## 上界

每个配置的 `coverage.json` 里行覆盖已经封顶，并且 `uncovered.txt` 里每一行都有下一步。封顶指该配置行覆盖最后一次上升之后不再上升。采样步数暂时保持 30。要加长时用 `spec/MC_for_sandtable_deep.tla`，不改 30 步 cfg。

达到上界才写 `行分类.tsv` 和 `未覆盖代码分类.md`。

## 完成标准

`行分类.tsv` 的行集合与最终的 `uncovered.txt` 一致，每一行都有集合、依据和下一步。A 和 B 的下一步写明加长、换常量，或已经放进 `scenarios.md`。E 在 `scenarios.md` 里有可以交回 Specula 的说明。C 和 D 在白名单里。摘要同时有并集行覆盖率和调整后行覆盖率。这些计数写入 `轮次报告.md`。`failures.tsv` 里还有未归类的行时，不要把本轮写成已经完成。
