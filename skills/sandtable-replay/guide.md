# 受控执行与差异分类

`sandtable-instrumentation` 完成之后，用随机轨迹检查可执行规格和 `artifact/<system>/` 是否走出同样的可见状态。单条轨迹能回放，只说明生成器认识 `pc`。这一阶段要求每种建模配置都跑完约定的条数。

路径相对 `<run>`，定义见 `sandtable-workflow-overview.md`。一轮受控执行是 `controlled-execution-runs/<轮次>/`，下面一种建模配置一个子目录。

## 输入 / 输出

**输入**：`spec/MC_for_sandtable.tla` 和每一份 `spec/MC_for_sandtable*.cfg`，`sandtable/testcase_generator.py`，`artifact/<system>/`，节点数等于 `Cardinality(Server)`。

**输出**：

- `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`
- 同目录的 `traces.txt`、`log.host`
- 每条轨迹的判决和实现侧墙钟，记入该配置的 `coverage.json` 时与 `sandtable-coverage` 共用同一次回放
- 潜在 bug 在 `potential-bugs/<短名>/`，格式见 `references/mismatch-record.md`

墙钟包住一次 `run_one_testcase.sh`，从启动控制器到日志结束。TLC 的时间另计，不写进这条耗时。

## 步骤

1. 按 `references/tlc-simulate.md` 为每种配置采样。默认每种 100 条，种子 `1` 到 `100`。行为里必须出现 `pc |->`。
2. 对每条 `MC.out` 执行 `run_one_testcase.sh <MC.out> <节点数>`。不要加 `-it`。节点数与模型里的 `Server` 相同。回放结束后把 `MC.out`、`traces.txt`、`log.host` 放进 `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/`。
3. 按 `references/compare-verdict.md` 判决。记下墙钟、是否 `logout`、变量断言、`net-len` 警告。
4. 变量对不上时先归类，再决定改规格还是写 bug 记录。
5. 同一轮次、同一配置上再加 trace 时，轨迹编号接着上一批，不覆盖已有的 `tNNNN`。`Sand*`、源码、驱动或生成器改了之后新开一轮次，旧目录保留。新轮次里每种建模配置重新采样、重新回放。

## 归类

读失败那一步的 `pc`、`log.host` 里的代码值与模型值，以及库里对应的控制流。

**适配层。** 可执行动作或生成器没有发出库在这一步实际发出的系统调用，或盖错了序号、提交点、条目。原规格若已有这条分支，把 `Sand*` 收到驱动实际走的分支上。改完新开一轮次，从步骤 1 重跑。

**潜在 bug。** 规格描述的是库的这条路径，代码的可见状态仍然不同；或者两边一致地做出规格标明的偏离。按 `references/mismatch-record.md` 把 `MC.out`、`traces.txt` 和 `log.host` 放进 `potential-bugs/<短名>/`。规格保持不动，不用改 `artifact/<system>/` 或驱动去抹平这条记录。

**环境。** 投递循环里连接被关掉、队列检查一直失败。变量差异是因为这一步没有在节点上执行。记录现象和日志位置，与协议赋值分开。

比较通过只说明这一步的可见变量相等。规格和代码一起写入一个偏离协议的值时，仍然记入潜在 bug，并附上该轨迹。

## 完成标准

每种配置的约定条数都有判决。适配层引起的变量断言已经消失，或者剩下一份写明原因的 bug 记录。覆盖率曲线交给 `sandtable-coverage`，它使用同一批回放。
