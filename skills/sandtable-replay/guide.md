# 受控执行与差异分类

`sandtable-instrumentation` 完成之后，用随机轨迹检查可执行规格和 `artifact/<system>/` 是否走出同样的可见状态。单条轨迹能回放，只说明生成器认识 `pc`。容器、挂载盘和拦截器见 `references/runtime.md`。

路径相对 `<run>`，定义见 `sandtable-workflow-overview.md`。一轮受控执行是 `controlled-execution-runs/<轮次>/`，下面一种建模配置一个子目录。启动脚本是 `sandtable/scripts/run_round.py`。

## 输入 / 输出

**输入**：`spec/MC_for_sandtable.tla` 和每一份 `spec/MC_for_sandtable*.cfg`，`sandtable/testcase_generator.py`，`artifact/<system>/`，节点数等于 `Cardinality(Server)`。

**输出**：

- `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`，同目录的 `traces.txt`、`log.host`
- `controlled-execution-runs/<轮次>/failures.tsv`：每一条失败轨迹一行。格式见 `references/mismatch-record.md`
- 潜在 bug 在 `potential-bugs/<短名>/<轨迹>/`，该类的每一条轨迹都拷贝
- 轮次结束时的 `controlled-execution-runs/<轮次>/轮次报告.md`，模板见 `references/round-report.md`

墙钟包住一次 `run_one_testcase.sh`，从启动控制器到日志结束。TLC 的时间另计。

## 一条轨迹

1. 按 `references/tlc-simulate.md` 采样。默认每种配置 100 条，种子从 1 起。行为里必须出现 `pc |->`。`MC.out` 先写进该轮次的 `traces/tNNNN/`。
2. `run_round.py` 把 `artifact/` 和 `sandtable/` 同步到挂载盘，再执行 `run_one_testcase.sh <MC.out> <节点数>`。不要加 `-it`。
3. 生成器按 `pc` 写 `traces.txt`。`controller` 发命令，`n1` 起的节点在拦截器下跑驱动。
4. 按 `references/compare-verdict.md` 判决。把 `traces.txt` 和 `log.host` 留在该轨迹目录。

## 失败时

立刻把这条写入 `failures.tsv`，暂停继续采样，再归类。

**适配层或模型。** `Sand*`、生成器或驱动没有走出库的这次系统调用，或序号、提交点、条目盖错了。原规格已有这条分支时，把 `Sand*` 收到驱动实际走的分支上。修好后新开一轮次，从采样重跑。不把旧 gcda 并进新轮次。

**潜在 bug。** 规格描述的是库的这条路径，可见状态仍然不同；或者两边一致地做出规格标明的偏离。按 `references/mismatch-record.md` 把该类每一条轨迹的 `MC.out`、`traces.txt`、`log.host` 拷进 `potential-bugs/<短名>/<轨迹>/`。然后在同一轮次继续，不新开一轮。

**环境。** 连接被关掉、队列检查一直失败，这一步没有在节点上执行。修好后在同一轮次继续。

**崩溃。** 没有 `logout`、进程非 0，或容器没有起来。归进潜在 bug 的继续本轮；归进适配层或环境的按上面两条处理。

比较通过只说明可见变量相等。规格和代码一起写入偏离协议的值时，仍然记成潜在 bug。

## 继续采样

同一轮次、同一配置上再加 trace 时，编号接着上一批，不覆盖已有的 `tNNNN`。只有适配层或模型改动才新开一轮次。

## 完成标准

约定条数都有判决。`failures.tsv` 里每一行都已归类。适配层失败已经在新轮次里消失，或者本轮报告写明新轮次的目录。每条潜在 bug 都能用 README 里的命令复现。覆盖率交给 `sandtable-coverage`。全文写进 `轮次报告.md`。
