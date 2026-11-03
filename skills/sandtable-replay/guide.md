# 受控执行与差异分类

`sandtable-instrumentation` 完成之后，用随机轨迹检查可执行规格和 `<ce>/system/` 是否走出同样的可见状态。单条轨迹能回放，只说明生成器认识 `pc`。容器、挂载盘和拦截器见 `references/runtime.md`。

路径里的 `<run>` 和 `<ce>` 见 `sandtable-workflow-overview.md`。一轮受控执行是 `<ce>`，下面一种建模配置一个子目录。超过一条轨迹时把回放放在后台。正常轨迹不通知。每一条不一致、失败、崩溃、异常退出都通知。`<ce>/sandtable/scripts/run_round.py` 是这个循环的一种实现，技能不要求这个文件名。

## 输入 / 输出

**输入**：`<ce>/spec/MC_for_sandtable.tla` 和每一份 `MC_for_sandtable*.cfg`，`<ce>/sandtable/testcase_generator.py`，`<ce>/system/`，节点数等于模型的 server。

**输出**：

- `controlled-execution-runs/<轮次>/<配置>/traces/tNNNN/MC.out`，同目录的 `traces.txt`、`log.host`
- `controlled-execution-runs/<轮次>/failures.tsv`：每一条失败轨迹一行。格式见 `references/mismatch-record.md`
- 潜在 bug 在 `potential-bugs/<短名>/<轨迹>/`，该类的每一条轨迹都拷贝
- 轮次结束时的 `controlled-execution-runs/<轮次>/轮次报告.md`，模板见 `references/round-report.md`

墙钟包住一次 `run_one_testcase.sh`，从启动控制器到日志结束。TLC 的时间另计。

## 一条轨迹

1. 按 `references/tlc-simulate.md` 采样。默认每种配置 100 条，种子从 1 起。行为里必须出现 `pc |->`。`MC.out` 先写进该轮次的 `traces/tNNNN/`。
2. 把 `<ce>/system/` 和 `<ce>/sandtable/` 同步到挂载盘，再执行 `run_one_testcase.sh <MC.out> <节点数>`。不要加 `-it`。
3. 生成器按 `pc` 写 `traces.txt`。`controller` 发命令，节点容器在拦截器下跑驱动。节点数等于模型的 server。
4. 按 `references/compare-verdict.md` 判决。把 `traces.txt` 和 `log.host` 留在该轨迹目录。

## 失败时

立刻把这条写入 `failures.tsv` 并通知，再按 `references/mismatch-record.md` 归类。失败类 `crash` 只表示计划外的进程死亡。确认之前不改成 `adapter`、`bug`、`environment` 或 `spec`。受控的崩溃或恢复执行成功时不写入这张表。

**适配层。** 驱动、生成器或序号映射没有把库这次的发送、接收或读回交给比较。通知并停。修好后新开一轮次，从采样重跑。不把旧 gcda 并进新轮次。不查上游 issue。

**潜在 bug。** 库这一步违反协议，或两边一起写成偏离协议的值。模型值不是修补目标；协议要求的结果写在 README 里。按 `references/mismatch-record.md` 把该类每一条轨迹的 `MC.out`、`traces.txt`、`log.host` 拷进 `potential-bugs/<短名>/<轨迹>/`。检索该仓库的 issue 和 PR，在 README 写 `KNOWN` 或 `NOT_FOUND` 并附链接。`KNOWN` 保留轨迹和复现命令。`NOT_FOUND` 才作为新的潜在 bug 交出去。通知后在同一轮次继续，不新开一轮。

**规格。** 库这一步符合协议，公式多写、少写或引错了源码行。同样拷贝轨迹。通知并停。按 `references/mismatch-record.md` 的「规格对齐」把对不上的规格拷进 `<ce>/spec/`，只对照 `<ce>/system/` 的源码改公式，把每次修改记入 `<ce>/spec-repairs.md`。这一步不读驱动和生成器。改完回到 `sandtable-instrumentation`，用 `<ce>/spec/base.tla` 重新生成可执行规格和适配层，新开一轮再回放。不改库去贴公式，不查上游。再出现 `spec` 或 `adapter` 就再走对应的修复。交出去的那一轮，`failures.tsv` 里没有这两类。

**环境。** 连接被关掉、队列检查一直失败，这一步没有在节点上执行。通知。修好后在同一轮次继续。

**计划外崩溃。** trace 的当前 label 不是受控的崩溃或恢复，进程却非 0、没有 `logout`、容器没有起来、超时，或库 / sanitizer 打出 `Assertion`、`Sanitizer`、`stack smashing`。防御性编码把进程打死或报错退出时，也记这一类。归类写 `crash`，通知并停。拷贝 `log.host`、`replay.status` 和 sanitizer 输出。先保持 `crash`，不查上游。确认时用协议语义。确认是实现违反协议后把归类改成 `bug`，README 写明表现是崩溃或 sanitizer，再查上游。确认是公式把一次符合协议的退出写成了别的状态，改成 `spec`，再按「规格对齐」修好并新开一轮。控制器的 `Variable ... compare failed` 按 `references/mismatch-record.md` 的顺序归类。

当前 label 就是受控的崩溃或恢复时，这一步按 `sandtable-instrumentation` 的 `references/controllability.md` 执行。进程按该步停住或从持久副本拉起，并且变量与公式一致，不算上一段的 `crash`。副本没有真的写入，或恢复没有从副本读回，记 `adapter`。

比较通过只说明可见变量相等。规格和代码一起写入偏离协议的值时，仍然记成潜在 bug。比较失败先分清适配层、协议和规格，见 `references/mismatch-record.md`。

覆盖率轮次之后，可以用同一批 `MC.out` 另开一轮 sanitizer 构建。构建见 `sandtable-instrumentation` 的 `guide.md`。那一轮里计划外的报告记 `crash`，gcda 不并入覆盖率轮次。受控的崩溃不记入。

## 继续采样

同一轮次、同一配置上再加 trace 时，编号接着上一批，不覆盖已有的 `tNNNN`。续跑跳过已经有判决的轨迹。适配层、可执行规格、协议公式副本、源码、驱动或生成器改动之后新开一轮次。`spec` 按「规格对齐」改公式，不留在未改的本轮里继续采样。计划外 `crash` 记录写完后，可以从下一条还没有判决的轨迹在本轮续跑。受控的崩溃或恢复不中断采样。

## 完成标准

约定条数都有判决。`failures.tsv` 里每一行都已归类，并且没有 `adapter` 和 `spec`。还有这两类时，这一轮不能当作完成。保持 `crash` 的行算已归类。改成 `bug` 的崩溃要有 `KNOWN` 或 `NOT_FOUND`。发现过的 `spec` 在当时那一轮的 `<ce>/spec-repairs.md` 里有原公式、源码位置和改后的公式，README 指向这次记录。每条 `bug` 都能用 README 里的命令复现。本轮副本和基线有差异时，`<ce>/patches/` 已按 `sandtable-instrumentation` 的 `references/patches.md` 重新生成，并且打补丁后的文件和副本一致。覆盖率交给 `sandtable-coverage`。全文写进 `轮次报告.md`。
