# case-011/r1 试点监视：skill、工具、环境、任务说明问题清单（最终版）

已审阅到第 2709 行（日志末尾），时间 2026-11-25 20:40 UTC。

## run 概况

- 起止：18:21:09 启动，约 20:24 UTC 结束（EXITED_0，result `success`，`end_turn`）。
- 成本：总耗时约 2 小时，API 时间 2971 秒，费用 31.6 美元。
- 工具调用：Bash 208 次，Write 13 次。MCP 工具一共只用了 6 次：`get_tlc_summary` 3 次、`get_tlc_state`、`compare_tlc_states`、`run_vav_analysis` 各 1 次。
- 没有用过的工具：`start_tlc`、`wait_tlc`、tracedebugger 的任何工具。
- 有发现时，本清单不评价 bug 结论本身。
- 思考正文在日志里为空（被隐藏），意图只能从 tool_use、assistant 文本和少量摘要式思考判断。

## 标记说明

- 状态：【已触发 N 次】有日志证据；【潜在】agent 接触过相关内容，但没有表现出问题；【未触发】整个 run 都没出现。
- 建议处理方：实验脚本 / 上游 skill / 上游工具 / 不处理（agent 自身失误或一次性问题）。

## 最后一轮（第 2349–2709 行）要点

- **liveness**：全程没有 liveness 反例。`get_tlc_summary` 第 3 次调用的对象是 discharge 检查，结果是 `violation_type: "action_property"`、`violation_name: "DischargeContext"`（第 2364 行）。三次调用都识别正确，`lasso` 都是 null。`compare_tlc_states`（第 2366 行）和 `get_tlc_state`（第 2526 行）返回正常，agent 用它们定位了变化的变量。
- **ci-result**：第 2694 行收尾时又跑了一次，返回 "Generated and validated CI results: FAIL."，没有报错。第 2698 行检查了 `spec/persistent-findings/`，生成了 MC-1、MC-2 的记录。
- **final-response.json**：第 2706 行写到 `/work/current/final-response.json`，取值 `decision: MODEL_UPDATED`、`workflow_status: COMPLETED_WITH_LIMITED_COVERAGE`、`blockers: []`。`findings_paths` 列了 `final-result.json`、`findings.json`、`bug-report.md`、`confirmation-*.md` 和 `cex-*.log`。agent 用 python 对照 `final-schema.json` 检查了必填字段和 enum，输出 "schema ok"（第 2707 行）。summary 里写明了 `MODEL_CHANGE_REQUIRED` 映射为 `MODEL_UPDATED`。最后一条消息就是这个 JSON（第 2708 行）。两套输出的关系 agent 自己理顺了，没有表现出困惑。
- **收尾清理**：
  - 第 2659 行用 `pgrep -a java` 和 `pgrep -fa "tlc2|cargo|lane"` 检查后台进程，又 `ls -la /dev/shm/specular-e2e-case-011/`，目录为空（第 2660 行）。
  - 第 2684 行补跑的两个 canary 之后再次确认目录为空，并确认 `artifact/` 是干净的。
  - `validation-summary.json` 在第 2590 行重写（P-2 解决）。
- **completion marker 和 controller**：最后一段没有任何相关字样，agent 没有输出自造的完成标记，也没有停下来等 controller。

---

## Skill

### S-1 guide 默认有 CI controller，一次性 run 里不存在【已触发 1 次，agent 正确处理】
- 描述：
  - `incremental-modeling/guide.md` 依赖 `request_context_compaction`、"The controller runs the one-shot confirmation workflow and resumes this conversation"，以及未定义的 "emit the completion marker"。
  - `references/reproduction/01-confirm-counterexample.md` 第 24 行要求 "call `request_bug_confirmation`"。
  - 本 run 没有这两个工具，也没有 controller。
- 证据：
  - 第 8 行，guide 原文。
  - 第 1 行，init 的工具列表里没有这两个工具。
  - 第 2299 行，agent 在 changelog 中写道："performed in this conversation because the `request_bug_confirmation` controller tool is not available here"。
- 影响：
  - agent 自己做了复现，没有卡住，也没有输出完成标记。
  - 但这是靠模型的判断兜住的，换一个模型或一个 case，可能会停下等待，或者跳过复现。
- 建议处理方：**上游 skill**，并配合 **实验脚本**。
  - guide.md 的 Part 4 和 "Readiness and Final Reporting" 两节，以及 `01-confirm-counterexample.md` 第 24 行，加上"没有 controller 工具时，在本会话内直接按 bug-confirmation 执行，不输出完成标记"。
  - 写明 completion marker 的具体内容，或者删掉这句。
  - task.md 里注明本 run 没有 controller。

### S-2 task.md 的 "standard convergence" 与 guide 的预算型完成规则不一致【未触发】
- 证据：
  - 第 12 行 task.md："Execute standard convergence"。
  - 第 8 行 guide："budgeted completion rules take precedence over convergence"。
- 影响：agent 一直按预算型规则执行，并把结果记为 LIMITED_COVERAGE，没有犹豫。
- 建议处理方：**实验脚本**。把 task.md 的措辞改成"按 incremental Part 3 的预算型完成规则"。

### S-3 skill 只给了跑不起来的 shell 包装，从没提到 `start_tlc`/`wait_tlc`，导致全程手工管理 TLC【已触发，贯穿全程】
- 描述：
  - `tla-checking-workflow/guide.md`（第 53、114–117 行）和 `bug-confirmation/guide.md`（第 60 行）都要求用 `scripts/infra/start_background.sh` 加 `wait_for_pid.sh`。
  - `/work/tools/start_background.sh` 依赖同目录的 `run_model_check.sh`，但这个脚本不在那里。
  - 已挂载的 `specular_tlc` 工具在所有 skill 里一次都没出现。
- 证据：
  - 第 1173 行（思考）："The provided start_background.sh relies on a missing run_model_check.sh, so I'm writing a small bounded runner"。
  - 第 1174 行写 `harness/tlc-run.sh`，用 `nohup ... &` 启动。
  - 之后 30 多次 TLC 运行全部走这个自写脚本。
- 影响：
  - 绕开了 `.tlc-tasks` 的任务记录、owner 锁和退出码记录。
  - 进度靠 tail 日志和 until 循环反复查看，估计浪费 15 轮以上。
  - 间接引出了 E-4（等待命令被拦截或转到后台）和 E-6（`pkill -f` 把自己的 shell 杀掉）。
  - agent 收尾时自己清理干净了，没有残留。
- 建议处理方：**上游 skill**，并配合 **实验脚本**。
  - 两个 guide 改成首选 `start_tlc(work_dir, spec_file, config_file, options)` 加 `wait_tlc(task_ids, mode)`，shell 包装只作为后备。
  - 实验脚本要么把 `run_model_check.sh` 一起放进 `/work/tools/`，要么不提供 `start_background.sh`。

### S-4 Trace.tla 的"默认 trace"兜底会掩盖环境变量名写错【已触发 1 次（先验套件需要迁移），潜在误报风险】
- 描述：
  - `spec-generation/guide.md` 第 95–98 行规定，`JsonFile` 在 `JSON` 未设置时退回一个默认 trace 文件。
  - 先验 Trace.tla 用的是 `IOEnv.SPECULA_TRACE`，agent 改成按 `JSON`、`SPECULAR_TRACE`、默认 trace 的顺序取值。
  - 如果环境变量名写错，TLC 会去验证默认 trace，照样报 "No error"，造成假通过。
- 证据：第 972 行。
- 影响：本 run 没有因此出错。各 trace 的状态数不同（第 1061、1123 行），说明读的确实是各自的 trace。
- 建议处理方：**上游 skill**。
  - 默认分支改成 `Assert(FALSE, ...)`，或者要求断言 `Len(TraceRecords)` 等于 trace 文件行数。
  - 统一只认 `JSON` 一个变量名。

### S-5 incremental 说 final-result 取代旧报告，但下游 skill 仍要求写 bug-report.md、findings.json【已触发 1 次】
- 证据：
  - 第 1998 行写 `bug-report.md`，第 2001 行写 `findings.json`（`"generated_by": "validation-workflow"`），第 2220 行再写 `final-result.json`。
  - 第 2706 行，`final-response.json` 的 `findings_paths` 把这三份都列上了。
- 影响：
  - 多花约 3 轮，第 2549 和 2692 行还要同步更新 `bug-report.md`。
  - 两套 findings 需要人工保持一致。
- 建议处理方：**上游 skill**。在 incremental guide 的 "Reuse the Existing Specular Methods" 一节列出：增量 CI 不再需要的下游产物是 `findings.json` 和 `bug-report.md`；仍然需要的是 `confirmation-*.md`。

### S-6 Generation 阶段只允许语法和静态预检，open 规格的 TLC 运行期错误要等 campaign 跑起来才暴露【已触发 1 次】
- 描述：
  - guide 的 "Current Stop Boundary" 规定，Generation 阶段只能做 syntax 和 static preflight。
  - `Update.tla` 的 open spec 里有逐下标的 primed 约束，SANY 能通过，但 TLC 运行时报变量赋值错误（exit 75）。
  - 这个错误直到 campaign 阶段才被发现，同时还发现 discharge 的写法需要改成 `EXCEPT` 形式。
- 证据：
  - 第 2477 行："The open check failed to start (exit 75)"。
  - 第 2500 行："TLC rejects per-index primed constraints in the open spec's next-state relation"。
  - 第 2507 行，kill 掉已经跑了约 10 分钟的 discharge-full，把日志改名为 superseded，然后重跑。
- 影响：浪费了一轮 discharge campaign（约 10 分钟）和约 3 轮对话。
- 建议处理方：**上游 skill**。
  - 允许，并且要求，在每个新 cfg 进入 campaign 前做一次极小的 TLC 冒烟运行，例如 `-depth 2` 或几步 simulate，用来抓取值和赋值类错误。
  - 在 `modular-verification.md` 里给出 `EnvUpdate` 的 TLC 可赋值写法（`EXCEPT` 形式），作为示例。

## 工具

### T-1 `run_vav_analysis`：CFG 构建失败时仍返回 `success:true`、`issues:[]`，摘要写"没有问题"【已触发 1 次，返回结果误导】
- 证据：
  - 第 915 行，返回 `"summary": "No variable assignment issues found..."`，但同一结果的 raw_output 里有 `ERROR: CFG building failed: Variable '"1"' in alias 'ReferenceNodeOrder' is not defined`。
  - 第 919 行，agent 识破了这个问题，之后不再使用 VAV。
- 影响：
  - 只看 summary 的 agent 会把它当成通过。
  - 触发条件是常量别名，这在 spec 里很常见。
- 建议处理方：**上游工具**。
  - `tools/spec_analyzer/src/spec_mcp/handlers/vav_handler.py`：raw_output 里出现 `ERROR:` 或 `CFG building failed` 时返回 `success:false` 和 `error_type`，`_generate_summary` 不能在分析未执行时输出"无问题"。
  - 修复 CFG builder 对常量别名的处理。

### T-2 tracedebugger MCP 加载了但全程没用，trace 验证和调试都走自写脚本和手工 grep【已触发，贯穿验证阶段】
- 证据：
  - 第 912 行，ToolSearch 加载了 `run_trace_validation` 等工具。
  - 第 1058、1120、1402 行用 `harness/validate-traces.sh` 做验证。
  - 第 1078、1084 行手工 grep cursor 调试。
- 影响：结果正确，21 条 trace 全部通过。但工具的定位能力没有用上，先验 Trace.tla 只认旧变量名可能是诱因。
- 建议处理方：**上游 skill**。在 `incremental-modeling/references/validation/03-trace-validation-loop.md` 写明：批量验证可以用脚本并保存为证据，但调试失败的 trace 必须先用 `run_trace_validation` 或 `run_trace_debugging`。

### T-3 `get_tlc_summary` 的 actions 大多是 "MCNext"，看不出子动作；类型识别正确【已触发 3 次】
- 证据：
  - 第 1479、1631、2364 行，三次的 `violation_type` 都是 `action_property`，`violation_name` 分别是 `PreVoteStaleResponseIgnored`、`TimerPreVoteElectionFromFollowerState`、`DischargeContext`，都正确。
  - `action_frequency` 里 `MCNext` 分别出现 3、10、8 次。
  - agent 每次都回到原始日志用 awk 解析（第 1480、1632 行），或者改用 `compare_tlc_states`（第 2365 行）。
  - 全程没有 liveness 反例，liveness 情况下的表现无法评估。
- 建议处理方：**上游工具**，并配合 **上游 skill**。
  - summary 遇到 Next 或 MCNext 这类包装动作时，附上每一步发生变化的变量（`compare_tlc_states` 已经有这个能力，可以合并进来）。
  - `mc-spec-pattern.md` 要求 MC 的 Next 由命名子动作析取组成。

### T-4 `specular findings`：子命令靠猜，空结果没有说明【已触发 1 次，轻微】
- 证据：
  - 第 1518 行，agent 试了 `list`，被拒绝。
  - 第 1519 行，`lookup` 只返回 `[]`。
- 影响：浪费半轮。
- 建议处理方：**上游工具**，并配合 **实验脚本**。
  - findings CLI 增加 `list`，`lookup` 结果为空时输出"N 条记录，0 条匹配"。
  - task.md 写明 `lookup --query` 的用法。

### T-5 `specular ci-result`：两次运行都直接通过，输出清楚【正面记录，附一个小问题】
- 证据：第 2226 行和第 2694 行都输出 "Generated and validated CI results: FAIL."；第 2698 行确认生成了 persistent-findings 记录。
- 小问题：生成的 `bug-severity.md`、`ci-report.md`、`confirmed-bugs.md` 权限是 0600，其他产物是 0644（第 2228 行）。
- 建议处理方：**上游工具**（低优先级）。ci-result 写文件时按默认 umask。

### T-6 `specular_tlc` 只有 start 和 wait，没有 stop【已触发（间接），见 E-6】
- 证据：
  - 第 1914 行用 `pkill -f`，第 1983 行和第 2507 行遍历 `/proc/*/cmdline` 后 kill，都是 agent 自己停止 TLC 的手段。
- 建议处理方：**上游工具**。在 `tools/tlc_tools` 和 `src/specular/tlc_tasks.py` 增加 `stop_tlc(task_ids)`。

## 环境

### E-1 先验套件引用 V0 环境的路径（`/work/old-tree`、`/work/source`、`/work/scope.md`），新源码也有两份【未触发】
- 证据：第 10、22、24 行。
- 影响：全程 agent 没有去找这些路径，直接用 `artifact/` 和 `old-source/`。
- 建议处理方：**实验脚本**（低优先级）。在 manifest 里加一张路径对照表，或者注明 `model-scope.md` 的 Authority 一节只适用于 V0。

### E-2 先验的 instrumentation.patch 在 update 上无法应用【已触发 1 次】
- 证据：
  - 第 922 行，`patch failed: openraft/src/engine/mod.rs:54`。
  - 第 980 和 1026 行，agent 重写 harness 源文件并重新生成 patch。
- 影响：约 3 轮，没有降级。这是正常的 rebase 冲突，不是提交号的问题。`validation-summary.json` 里的旧提交号 `b41ce98` 没有造成困惑。
- 建议处理方：**不处理**。属于 rebase 的正常工作量。可以顺手让实验脚本在中性化时同步改写先验里的 commit 字段。

### E-3 先验 harness 带旧名字、旧路径，并依赖沙箱里没有的 `rg`【已触发；agent 已全部补改】
- 描述：
  - 先验 harness 用的是 `SPECULA_TRACE`、`SPECULA_TRACE_PATH`、`SPECULA_WORK_SOURCE`（默认 `/work/work-source`）、`SPECULA_*_TIMEOUT`、`/dev/shm/specula-v0-case-011`、`specula_trace_*`。
  - 结果判定用 `rg -q`，但沙箱里没有 `rg`（第 194 行）。
  - README 说 nightly-2026-03-01 不可用，可是沙箱里已经装了。
- agent 的处理：
  - 第 1026 行重写了 `run.sh`、`apply-instrumentation.sh`、`validate-traces.sh` 和 Rust harness。
  - 第 1880 行重写了 README。
  - 第 2246 行重写了 `run-model-check.sh`。
  - 最终只剩两处故意保留的先验副本：`harness/patches/v0-instrumentation.patch` 和 `spec/evidence/E-LogNone/Trace.tla`。后者运行时也设置了 `SPECULA_TRACE`（第 1388 行）。
- 影响：
  - trace 验证没有因为旧名字失败。
  - rebase 加上残留补改，一共约 5 轮。
- 建议处理方：**实验脚本**。
  - 冻结 prior 时统一把 `SPECULA_*`、`specula-` 迁移成新名字，去掉 `rg` 依赖，或者在镜像里装 ripgrep。
  - 可选（**上游 skill**）：在 `01-reuse-prior-harness.md` 加一条，rebase 后用 grep 查一遍旧名字和旧路径。

### E-4 前台 `sleep` 被拦截，Bash 默认 120 秒超时把等待命令转到后台【已触发 3 次】
- 证据：
  - 第 1333 行 `Blocked: sleep 60 ...`。
  - 第 2283 和 2310 行 "Command did not complete within its 120s timeout and was moved to the background"。
  - 第 2315 行起，agent 显式传 `"timeout": 600000`，之后不再出现。
- 影响：浪费 3 轮。
- 建议处理方：**上游 skill**，根本解决要靠 S-3。在 `tla-checking-workflow/guide.md` 的等待说明里写明：用 `wait_tlc`；如果要用 shell 等待，必须同时设置工具层的 timeout。

### E-5 先验 V0 模型选不出 leader，属性一直被空洞满足，V0 冻结时没有发现【已触发】
- 证据：
  - 第 1377 行："no leader can be elected from the initial state ... NoLog records carry the node id"。
  - 第 1408 行，补充了 canary。
- 影响：agent 修复了这个既有缺陷，并新增 2 条 trace，约 5 轮。这说明先验 prior 的质量门没有检查非空洞性。
- 建议处理方：**实验脚本**。V0 冻结门要求至少有一个"选出 leader 或提交"之类的可达性 canary 被违反，否则不冻结。也可以（**上游 skill**）在 spec-generation 和 validation-workflow 里把可达性 canary 列为必需项。

### E-6 用 `pkill -f <label>` 停 TLC 时把执行命令的 shell 也杀了【已触发 1 次】
- 证据：
  - 第 1914 和 1916 行，退出码 144，后面的清理和 cfg 修改都没执行。
  - 第 1925 行重新执行了这些步骤。
  - 之后 agent 改为遍历 `/proc/*/cmdline` 再 kill（第 1983、2507 行），没有再出问题。
- 影响：浪费 2 轮。
- 建议处理方：**不处理**，算 agent 的一次性失误。根本解决靠 S-3 和 T-6。

### E-7 TLC 用 `stopAfter` 按时间截断时仍打印 "Model checking completed. No error has been found."【已触发，agent 判断正确】
- 证据：
  - 第 2331 行，日志里队列还剩 1134 万个状态。
  - 第 2571 和 2654 行也是同样的情况。
- 影响：
  - agent 一直结合 "states left on queue" 判断，结果记为 budget-limited。它的 `summarize_campaigns.py`（第 2583 行）也单独处理了这种情况。
  - 但任何只 grep "No error" 的脚本都会误判。
- 建议处理方：**上游 skill**，并配合 **上游工具**。
  - skill 写明判断是否完成要看队列是否为 0。
  - `get_tlc_summary` 和 `wait_tlc` 返回 `queue_remaining` 和 `stopped_by_budget`。

### E-8 沙箱的私有 `/dev/shm`、独立 PID 命名空间和 `--die-with-parent`【环境说明，已核实】
- 描述：
  - 沙箱有独立的 PID 命名空间和私有 `/dev/shm`，并且用了 `--die-with-parent`，会话结束时进程和状态目录会自动销毁，不会泄漏到宿主机。
  - 第 2659–2660 和 2684 行，agent 收尾时确认没有 java 进程，状态目录为空。
- 次要观察：
  - 在沙箱的 PID 命名空间里，PID 1 是 bwrap，它的完整命令行对 agent 可见，里面有宿主机路径：`/mydata/bingzhuo/inv-e2e-epoch2-pilot/neutral/<hash>/...`、`attempts/v2/case-011/r1/log/mcp-config.json`、`main-tools-specular`。
  - 第 2660 行，agent 的 `pgrep -fa "tlc2|cargo|lane"` 因为匹配到 `cargo` 而打印了这一整行。
  - 命令行里没有 Gold 或评分路径，但能看出实验和 arm 的命名。
- 建议处理方：**实验脚本**（低优先级）。
  - 用一个极小的 init 包装（例如 `bwrap ... -- /opt/init-shim`），或者把绑定挂载改为先挂到中性路径，避免宿主机目录结构通过 `/proc/1/cmdline` 暴露。
  - 在 stop-gate 时于沙箱内记录一次 `pgrep java` 和 `ls /dev/shm` 的结果，写进 manifest。

## 任务说明

### P-1 两套最终输出（final-schema 和 final-result），字段和位置都不同【未造成困惑】
- 证据：
  - 第 2706–2707 行，agent 按 schema 自检，输出 "schema ok"。
  - `decision` 填 `MODEL_UPDATED`，`workflow_status` 填 `COMPLETED_WITH_LIMITED_COVERAGE`。
  - `findings_paths` 混列了 `final-result.json`、`findings.json`、`bug-report.md`、`confirmation-*.md` 和 `cex-*.log`。
  - `final-response.json` 写在 `/work/current/`，与"所有输出都放在 `.specular-output/` 下"的要求存在字面冲突，agent 没有提出疑问。
- 影响：没有浪费轮次。但 `findings_paths` 该填什么没有约定，不同 run 之间写法会不一致，评分端需要自己适配。
- 建议处理方：**实验脚本**。
  - 在 task.md 定义 `findings_paths` 的内容，例如只列 `final-result.json` 和每个 finding 的 evidence。
  - 说明 `NEEDS_FULL_REMODEL` 何时使用。
  - 注明 `final-response.json` 是输出位置规则的例外。

### P-2 先验的 `validation-summary.json` 留在当前输出目录里【已解决】
- 证据：第 2590 行，agent 重写了 `validation-summary.json`。
- 建议处理方：**实验脚本**（低优先级）。播种 current 时把它改名为 `validation-summary.prior.json`，避免中途被误读。

## 其他观察（不算问题）
- 第 5 行：skill 从 `/work/.claude/skills/` 加载，task.md 说的是 `.agents/skills`，task.md 已说明两者相同，agent 没有困惑。
- 第 29–30 行：52KB 的输出被截断后，agent 改用 Read 读全文，属于正常行为。
- 第 1179 行：`tail -3 f1 f2` 的语法错误，是 agent 自己的一次性失误。

---

## 按处理方汇总

**实验脚本**
- S-1（附带）：task.md 注明没有 controller，Part 4 由 agent 自己执行。
- S-2：把 "standard convergence" 改成预算型完成规则。
- S-3（附带）：要么把 `run_model_check.sh` 放进 `/work/tools/`，要么不提供 `start_background.sh`。
- T-4（附带）：task.md 写明 `specular findings lookup --query` 的用法。
- E-1：给出 V0 路径到本沙箱路径的对照，或者注明 Authority 一节只适用于 V0（低优先级）。
- E-3：冻结 prior 时迁移旧名字和旧路径，去掉 `rg` 依赖，更新 README 的工具链说明。
- E-5：V0 冻结门增加可达性 canary（非空洞性）检查。
- E-8：避免 `/proc/1/cmdline` 暴露宿主机路径；在 stop-gate 时记录进程和 `/dev/shm` 状态。
- P-1：定义 `findings_paths` 的内容、`NEEDS_FULL_REMODEL` 的用法，以及输出位置的例外。
- P-2：播种 current 时把先验的 `validation-summary.json` 改名。

**上游 skill**
- S-1：补上没有 controller 时的分支，删掉或定义 completion marker 和 `request_bug_confirmation`。
- S-3：TLC 运行和等待首选 `start_tlc`/`wait_tlc`（tla-checking-workflow、bug-confirmation）。
- S-4：Trace.tla 的默认 trace 兜底改成断言，统一只用 `JSON` 变量名。
- S-5：说明增量 CI 不再需要的下游产物（`findings.json`、`bug-report.md`）。
- S-6：每个新 cfg 进入 campaign 前做 TLC 冒烟运行；给出 `EnvUpdate` 的 `EXCEPT` 写法示例。
- T-2：调试失败的 trace 必须先用 tracedebugger 工具。
- T-3（附带）：MC 的 Next 由命名子动作析取组成。
- E-3（附带）：rebase 后用 grep 检查旧名字和旧路径。
- E-4：等待时用 `wait_tlc`，或者同时设置工具层 timeout。
- E-5（附带）：可达性 canary 列为必需项。
- E-7：判断是否完成要看队列是否为 0。

**上游工具**
- T-1（紧急）：`vav_handler.py` 在分析失败时不能报成功；修复常量别名的处理。
- T-3：`get_tlc_summary` 遇到包装动作时附上变化的变量。
- T-4：findings CLI 增加 `list`，空结果给出说明。
- T-5：ci-result 生成的文件权限（低优先级）。
- T-6：`specular_tlc` 增加 `stop_tlc`。
- E-7（附带）：`get_tlc_summary` 和 `wait_tlc` 返回 `queue_remaining` 和 `stopped_by_budget`。

**不处理**
- E-2：先验 patch 的 rebase 冲突，属于正常工作量。
- E-6：`pkill -f` 自杀，agent 的一次性失误，根本解决靠 S-3 和 T-6。
- 其他观察里的 `tail` 语法错误和输出截断。
