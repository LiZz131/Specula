# 受控执行上的覆盖率

用同一批 `sandtable-replay` 轨迹，记录 `artifact/<system>/` 被执行到的行和分支。路径相对 `<run>`，定义见 `sandtable-workflow-overview.md`。覆盖率按配置分开累计。换配置时从零开始。同一轮次、同一配置里追加的 trace 接着累加。

## 输入 / 输出

**输入**：`controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`，`artifact/<system>/` 里带 `--coverage` 的库，以及 `sandtable/driver/` 里会在进程退出时把计数写盘的驱动。

**输出**：

- `controlled-execution-runs/<轮次>/<配置>/coverage.json`：第 k 条 trace 结束时的行覆盖、分支覆盖和墙钟。字段见 `references/report-format.md`
- `controlled-execution-runs/<轮次>/<配置>/gcov/*.gcov`：该配置累计到目前的 gcov 文本
- `controlled-execution-runs/<轮次>/lcov.info`：各配置 gcov 的并集。一行在任一配置里次数大于 0，`DA` 计数就大于 0。`SF` 用 `<run>/artifact/<system>/` 下的绝对路径。willemt/raft 是 `artifact/raft/`
- `controlled-execution-runs/<轮次>/uncovered.txt`：从这份 lcov 里计数为 0 的可执行行生成，一行一条，格式 `文件名:行号`

行覆盖取 gcov 的 Lines executed。分支覆盖取 Taken at least once，也就是该分支至少走过一次的比例。Branches executed 是另一列，报告里可以附上，曲线以 Taken at least once 为准。

## 步骤

1. 按 `references/gcov-gotchas.md` 准备库、驱动和退出时的 dump。确认一条短轨迹能写出非空的 gcda，并且库里已知跑过的函数计数大于 0。
2. 一个配置第一次回放前删除 gcda。同一配置继续追加 trace 时保留 gcda。换配置时从零开始。
3. 每条轨迹结束后，在容器里合并各节点的 gcda，再跑 `gcov -b`。把百分比和墙钟追加到该配置的 `coverage.json`。用这次 gcov 覆盖该配置的 `gcov/*.gcov`。
4. 这一轮用于分类的那一次，写轮次根上的 `lcov.info`，再从它生成 `uncovered.txt`。一行在任一配置里执行过就不算未覆盖。各配置的百分比不要加总。这两份文件交给 `sandtable-coverage-gaps`。
5. 各配置的 `gcov/` 在清掉 gcda 之前已经落盘，切换配置不丢失上一配置的文本。

## 曲线怎么读

第一条轨迹通常就覆盖初始化、选举和普通 AppendEntries。之后缓慢上升，直到某种动作第一次出现，百分比出现一次台阶。快照、加载快照属于这种台阶。

台阶之后长时间水平，表示剩下的代码不在这组 `pc` 能走到的路径上，或者采样太短，消息发出了还没被投递。把「从未执行」和「动作出现过但函数仍是 0 次」分开写进报告。后者优先交给缺口分类。

## 完成标准

每种配置都有 `coverage.json` 和 `gcov/`。轮次根上有并集 `lcov.info` 和由此生成的 `uncovered.txt`。并集的已执行行数写入 `轮次报告.md`。gcda 在进程中途被冻住时，曲线会从第一条就水平，已执行的函数却显示 `called 0`。出现这个形态时先按 `references/gcov-gotchas.md` 修正 dump，再重测覆盖率。轨迹判决本身不用因此重跑，除非回放进程也要换二进制。

sanitizer 轮次使用另一份二进制，复用本轮的 `MC.out`。它的 gcda 不进入这份 `lcov.info`，也不改这里的行覆盖数字。有 sanitizer 报告时按 `sandtable-replay` 记 `crash`。
