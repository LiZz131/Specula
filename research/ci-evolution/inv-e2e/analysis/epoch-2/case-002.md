# case-002（ZooKeeper Zab，NEWLEADER/UPTODATE 更新）epoch-2 run 分析

## 路径缩写与声明

- `E2/<arm>/r<n>/` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results-epoch2/<arm>/case-002/r<n>/`，其中 `out/` 是该目录下的 `output/`。
- `E1/<arm>/` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results/<arm>/case-002/r1/`（epoch-1，只作描述性对照）。
- `PRIOR/` = `/users/bingzhuo/Specula/research/ci-evolution/blind-incremental-bugs/blind-incremental-v0/case-002/.specula-output/`；`PRIOR-scope` = 同级的 `scope.md`。它与 `inputs/case-002/model-scope.md` 逐字节相同（`diff -q` 无输出）。
- `MECH` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/analysis/epoch-2/mechanics.md`。
- 引文保留英文原文。文中的 run 用 `v0r1`、`v1r2` 这样的简写。

**声明**：本分析没有读取任何 Gold、评分或答案材料，也没有读取 `notes/`、`analysis/epoch-1/`，以及 `blind-incremental-bugs` 下除 `PRIOR/` 和 `PRIOR-scope` 之外的内容。本文不判断任何发现是否为真 bug，只描述各 run 自己报告了什么，以及给出了什么证据。

补充说明：只读取了 v0 arm 的先前模型。`run.json` 中 v0 和 v1 的 `prior_tree_sha256` 相同（`cdd595f4…`），v2 的不同（`a5211a81…`），按实验设定差异只在注释。下面凡是与 `PRIOR/` 对照的结论，都以 v0 版先前模型为准。

---

## 1. 结果

### 1.1 总表（epoch-2）

6 个 run 的 `final-response.json` 都是 `"decision": "MODEL_UPDATED"`、`"workflow_status": "COMPLETED_WITH_LIMITED_COVERAGE"`，`blockers` 都为空。发现的状态取自 `out/spec/final-result.json`。

| run | 发现 id | 一句话机制（据 run 自述） | status | 来源 |
|---|---|---|---|---|
| v0r1 | MC-1 | NEWLEADER ACK 早于学习者对同步提案的 fsync，学习者崩溃后丢失 leader 已服务的事务 | REPRODUCED | model-checking |
| | MC-2 | 学习者在 NEWLEADER 和 UPTODATE 之间失败，因处于 INITIAL 状态而跳过 shutdown，DataTree 过期，进程内重选后丢失已服务事务 | REPRODUCED | model-checking |
| | MC-3 | TRUNC 到日志中不存在的 zxid 时保留了下一条记录（run 自称 "update-independent"） | REPRODUCED | model-checking |
| | CR-1 | NEWLEADER 时启动的处理器发出的逐事务 ACK 可能先于 NEWLEADER ACK | NEEDS MORE INFO | code-review |
| v0r2 | MC-1 | NEWLEADER quorum 提交了学习者只入队、尚未持久化的 DIFF 历史 | REPRODUCED（Critical） | model-checking |
| | MC-2 | SyncRequestProcessor 写出的 ACK 被当成 NEWLEADER ACK | REPRODUCED | model-checking |
| | MC-3 | NEWLEADER 之后到达的 COMMIT 对应 NEWLEADER 之前缓冲的提案，触发 NPE | REPRODUCED | model-checking |
| | CR-4 | INITIAL 状态学习者失败后处理器泄漏 | REPRODUCED | code-review |
| | CR-5 | pre-Zab1.0 同步路径从不启动学习者 server | REPRODUCED | code-review |
| v1r1 | MC-1 | NEWLEADER ACK 早于同步事务持久化 | REPRODUCED | model-checking |
| | MC-2 | INITIAL 状态下跳过 shutdown，过期的内存 DB 参与投票和领导 | REPRODUCED | model-checking |
| | MC-3 | 学习者的 txn ACK 可能先于 NEWLEADER ACK | REPRODUCED | model-checking |
| v1r2 | MC-1 | NEWLEADER ACK 早于 DIFF 同步历史持久化 | REPRODUCED | model-checking |
| | CR-1 | NEWLEADER 与 UPTODATE 之间到达的 COMMIT 访问空的 `packetsNotCommitted`，触发 NPE | REPRODUCED | code-review |
| | CR-2 | 同步失败（UPTODATE 前）后，NEWLEADER 时启动的处理器没有被关闭 | REPRODUCED | code-review |
| | CR-3 | SyncThread 的逐事务 ACK 抢在 NEWLEADER ACK 之前 | REPRODUCED | code-review |
| v2r1 | MC-1 | NEWLEADER ACK 早于 DIFF 同步事务持久化 | DEFERRED | model-checking |
| | MC-2 | 学习者在 NEWLEADER 和 UPTODATE 之间失败后保留过期内存 DB，之后的 leader 缺少已提交事务 | DEFERRED（Critical） | model-checking |
| | CR-1 | SyncThread 的提案 ACK 先于 NEWLEADER ACK，被当成 NEWLEADER ACK | NEEDS MORE INFO | code-review |
| v2r2 | MC-1 | NEWLEADER ACK 早于 DIFF 同步事务持久化 | REPRODUCED | model-checking |
| | CR-2 | 学习者失败后泄漏一个 INITIAL 状态的 ZooKeeperServer（处理器未关闭，数据树未 fast-forward） | REPRODUCED | code-review |
| | CR-3 | 提案 ACK 被当成 NEWLEADER ACK | REPRODUCED | code-review |

v2r1 的 DEFERRED 与其 `final-response.json` 的说法一致：“Part-4 reproduction was not run.”

### 1.2 r2 的 `ci-verdict.json` 状态分布

| run | 记录数 | REPRODUCED | 其他状态 | `ci-report.md` 中的结论 |
|---|---|---|---|---|
| v0r2 | 5（3 MC + 2 CR） | 5 | 0 | "CI verdict: **FAIL**. Reproduced bugs: 5; other unresolved findings: 0" |
| v1r2 | 4（1 MC + 3 CR） | 4 | 0 | "CI verdict: **FAIL**. Reproduced bugs: 4; …" |
| v2r2 | 3（1 MC + 2 CR） | 3 | 0 | "CI verdict: **FAIL**. Reproduced bugs: 3; …" |

`ci-verdict.json` 本身只有 `version`、`run_id` 和 `findings[]`（每条含 id、status、evidence、source），**没有总体 verdict 字段**；FAIL 只出现在 `ci-report.md` 里。三个 r2 都没有 FALSE POSITIVE、CANDIDATE 或 NEEDS MORE INFO。

### 1.3 r2 的 `final-result.json` 与 `final-response.json` 是否一致

- **发现 id 和状态一致。**
  - v0r2：final-response 写 "All five reproduced"，与 final-result 的 MC-1..3、CR-4、CR-5 均为 REPRODUCED 相符。
  - v1r2：final-response 写 "MC-1 was REPRODUCED … three update-introduced defects, all REPRODUCED"，与 MC-1、CR-1..3 相符。
  - v2r2：final-response 写 "MC-1 was reproduced … Two new defects from code review were also reproduced"，与 MC-1、CR-2、CR-3 相符。
- **`findings_paths` 全部存在**：脚本把每条路径映射到导出的 `out/` 下检查，6 个 run 的缺失数都是 0。
- **小的格式差异**：
  - `spec/findings.json` 收录的范围在不同 run 间不同。v1r2 只有 MC-1；v0r2 只有 MC-1..3；v2r2 收录了 MC-1、CR-2、CR-3，并带 `status` 字段。CR 发现完整出现在 `final-result.json`、`ci-verdict.json` 和 `spec/persistent-findings/` 中。
  - CR 编号不连续：v0r2 是 CR-4、CR-5，v2r2 是 CR-2、CR-3。v2r2 的 findings.json 中有 `bug_number` 字段，看起来 CR 沿用了全局编号。
- **r1 的旁证**：v0r1 内部编号不一致。`E2/v0/r1/out/analysis-report.md:68` 写 "recorded as code-review item CR-3"，但 `spec/bug-report.md:180` 和 `final-result.json` 中是 CR-1；`spec/findings.json` 不含这条 CR。

---

## 2. liveness 与推进性

### 2.1 有没有定义时序性质

**没有。** 6 个 epoch-2 run 都没有为被测系统定义时序性质（liveness）。

- 在全部 `.tla` 中搜索 `~>`、`[]<>`、`<>[]`、`WF_`、`SF_`，命中只有两类：
  - trace 验证里的 `TraceMatched == <>(l > Len(TraceLog))` 及其 `WF_traceAllVars(TraceNext)`，例如 `E2/v1/r1/out/spec/Trace.tla:621-623`、`E2/v2/r1/out/spec/Trace.tla:560-568`、`E2/v0/r1/out/spec/TraceUpdateCheck.tla:13`；
  - 文本里的 `<<>>`（空序列），不是时序算子。
- 各 cfg 的 `PROPERTIES` 中，除 `TraceMatched` 外都是动作性质 `[][…]_vars`：`HistoryPositionsMonotonicExceptRecovery`、`DischargeContext`/`UpdDischarge`、`UpdNewLeaderAckAfterDurable`（`E2/v2/r1/out/spec/Update.tla:179-182`）。
- `MECH` 中 case-002 六个 run 的 L1、L2、L3 三列都是 `-`。

### 2.2 有没有用 safety 写法表达推进或停滞

**有两个 run 把“确认顺序”写成了 safety 不变量**，但没有闭包不变量或停滞 canary。

- v0r2：`E2/v0/r2/out/spec/UpdateProps.tla:22` 定义 `NewLeaderAckFirst == \A s \in Server : ~nlAckMisread[s]`，是一个 ghost 错误标志式不变量。`modeling-brief.md:240-241` 给它的优先级写的是：

  > "**Priority**: High (liveness of epoch establishment; lost ACK for outstanding proposals)."

  同一文件还用同样的标志写法定义了 `SyncCommitHasPendingProposal == \A s \in Server : ~syncNPE[s]`。
- v1r1：`E2/v1/r1/out/spec/UpdateProps.tla:34-36`：

  > "P4 (new; R4): the first ACK a learner writes after NEWLEADER is the NEWLEADER ACK (otherwise the leader rejects it and never counts it). `NewLeaderAckIsFirstAck == \A s \in Server : ~ackShadowed[s]`"

- 其余 run 中的 canary 都是可达性取反，例如 v0r2 的 `Canary-NotAckBeforeNlAckReached.cfg`、v1r1 的 `Update-canary-NotAckShadowReached.cfg`、v2r2 的 `Update-canary-ackbeforedurable.cfg`。它们证明窗口可达，并不检测停滞。没有任何 run 写“必然最终建立 epoch”或“不会永久等待”之类的闭包或进度代理。

### 2.3 与推进、停滞、等待、确认顺序有关的发现

**6 个 run 都报告了“txn ACK 抢先于 NEWLEADER ACK”（第 4 节的机制 M4）**，但状态和定性不同。

- v0r1 CR-1（NEEDS MORE INFO）：后果写作 "may time out and re-elect (availability only)"（`final-result.json:97`）。
- v0r2 MC-2（REPRODUCED）：后果写作 "the re-elected leader fails to establish its epoch and times out"。
- v1r1 MC-3（REPRODUCED）：后果写作 "the learner is never counted and the leader cannot establish its epoch"。
- v1r2 CR-3（REPRODUCED）：后果写作 "the leader does not form its NEWLEADER quorum and stalls until the init limit"。
- v2r1 CR-1（NEEDS MORE INFO）：后果写作 "the leader may time out and abandon the epoch (availability), not a safety violation"。
- v2r2 CR-3（REPRODUCED）：后果写作 "activation waited for a learner sync timeout and re-sync (about 22 s versus under 4 s on the old revision)"。

另有两类发现的后果涉及推进：

- NPE 类（M5）：v0r2 MC-3 写 "the learner returns to LOOKING and cannot join under load"；v1r2 CR-1 写 "cannot join until a retry avoids the interleaving"。
- 处理器泄漏类（M3）：v0r2 CR-4、v1r2 CR-2、v2r2 CR-2。

### 2.4 run 怎么说明不做 liveness（原话）

- v2r1：`E2/v2/r1/out/brief-coverage.md:30`

  > "Liveness: none in the brief (prior or update); CR-1 is a liveness concern recorded for code review."

  同文件第 15 行："not modeled (packet order, liveness)"；`modeling-brief.md:279-280`："Not modeled in TLC (needs per-connection packet order and liveness)"。
- v2r2：`E2/v2/r2/out/ci-report.md:13`（`final-result.json:8`、`confirmed-bugs.md:48` 同文）

  > "CR-3 (proposal ACK consumed as NEWLEADER ACK) is a liveness/availability issue outside the safety model; confirmed only by reproduction."

  `brief-coverage.md:14`："not modeled (unordered messages; liveness)"。
- v1r2：`E2/v1/r2/out/ci-report.md:14`

  > "Not modeled: late joiners to a broadcasting leader, observers, reconfiguration, exception/liveness paths (handled by code review CR-1..CR-3)"

  `modeling-brief.md:260` 写 "Code-review scenarios (no model counterexample; outside safety granularity)"，并把 CR-1、CR-3 标为 "(liveness)"。
- v0r1：`E2/v0/r1/out/spec/bug-report.md:184-186`

  > "Availability only (leader may miss its quorum and re-elect). Not observed in fresh traces (`NewLeaderAckRejected` count 0); the FIFO learner channel is outside the model."

  `modeling-brief.md:66` 的排除项中有 "FIFO ordering of the learner channel (CR-1)"。
- v1r1：没有单独写出不做 liveness 的理由。它把该机制建模为 safety 不变量（P4），并在 `modeling-brief.md:240` 标注 "**Priority**: Medium (availability: learner not counted)"。
- v0r2：同样建模为 safety 标志不变量（见 2.2），没有其他关于 liveness 的说明。

### 2.5 先前模型中 “Wall-clock liveness” 排除项的处理

`PRIOR/modeling-brief.md:141-142` 原文：

> "- Wall-clock liveness and failure detectors: no fairness/availability claim is justified by the bounded environment."

- **6 个 epoch-2 run 都把这句话原样保留在 §3.2 “Do not model”中。** v0r1 在第 212 行（前面插入了更新章节），其余 5 个都在第 141 行。epoch-1 三个 run 也都保留（`E1/v0/out/modeling-brief.md:226`、`E1/v1/out/modeling-brief.md:159`、`E1/v2/out/modeling-brief.md:141`）。
- **没有任何 run 修改、引用或讨论这句话。** 在 `out/` 和 `timeline.md` 中搜索 `fairness/availability` 与 `failure detector`，命中只有上面这些原样保留的行。
- `PRIOR-scope`（也就是本 case 的公开 scope）写的是 "Liveness checks may be bounded and conditional on explicit fairness and fault assumptions. Never report a resource-limited liveness run as a proof."，没有任何 run 引用这句。
- 结果是：brief 中的 liveness 排除项原样保留；scope 中允许有界 liveness 的条款没有被采用；同一个 run 中，确认顺序类问题要么写成 safety 标志不变量（v0r2、v1r1），要么在 run 自己新增的章节里以 "liveness" 为由排除到模型之外（v0r1、v1r2、v2r1、v2r2）。

---

## 3. 继承

### 3.1 文档的原样继承

用脚本统计先前文档的非空行在 run 输出中出现了多少（按行原样匹配）：

| run | `PRIOR/modeling-brief.md`（148 行） | `PRIOR/analysis-report.md`（108 行） |
|---|---|---|
| v0r1 | 147（只改了标题） | 107（只改了标题） |
| v0r2 | 148 | 108 |
| v1r1 | 148 | 108 |
| v1r2 | 148 | 108 |
| v2r1 | 147（只改了标题） | 108 |
| v2r2 | 146（改了 §6.3） | 108 |
| E1 v1（对照） | 140 | 1 |

也就是说，epoch-2 的 6 个 run 都采用“先前全文保留，新增章节追加在后”的形式。原样带入的范围说明和排除项包括：

- §3.2 Do not model 的 4 条（`PRIOR/modeling-brief.md:135-142`）：
  > "Dynamic reconfiguration and observers …"、"Sessions, watches, ACLs, digests, and concrete znode payloads …"、"Socket framing, TLS/SASL, JMX, metrics, batching heuristics, and fsync latency: operational details not needed for protocol safety."、"Wall-clock liveness and failure detectors …"
- §6.3（`PRIOR/modeling-brief.md:186-189`）："None. This fresh prior did not identify a source defect requiring manual confirmation …"。5 个 run 原样保留，只有 v2r2 改写为 "V0: none. Incremental run (update 2efbdfc): CR-2 … and CR-3 …"（`E2/v2/r2/out/modeling-brief.md:186-191`）。
- `PRIOR/analysis-report.md` 结尾的 "No implementation bug is claimed and no property was weakened to obtain green output." 在 6 个 run 中都原样存在（如 `E2/v0/r2/out/analysis-report.md:136`），与同一文件后面追加的发现并存。v0r2 用 `# Incremental analysis — run …`（第 141 行）分隔先前部分和新增部分。

### 3.2 排除项的近似继承

在 run 新写的章节里，排除项几乎都是对先前或 scope 的复述，有时加上新的排除：

| run | 原文 | 与先前的关系 |
|---|---|---|
| v0r2 | `brief-coverage.md:42`："Excluded (unchanged from V0): observers, dynamic reconfiguration, sessions/ACL payloads, wire framing, metrics; additionally the pre-Zab1.0 UPTODATE-only path (D-4, legacy protocol)." | 明说继承；同时把 pre-Zab1.0 路径列为 out of scope，但仍以 CR-5 报告并复现 |
| v2r2 | `modeling-brief.md:270-275` "### 8.4 Exclusions (unchanged scope)"："Observers …, pre-Zab-1.0 leaders …, socket timeouts (`setSoTimeout` move), reconfiguration packets, metrics/JMX registration of the leaked processors." | 明说继承 |
| v1r2 | `modeling-brief.md:285-288`："Late joiners to an already-broadcasting leader remain excluded (prior restriction `EnterSyncPhase` requires the leader in SYNC); documented limit." / "Excluded: socket timeouts …, observers" | 明说继承了先前模型的结构限制（见 3.3） |
| v0r1 | `modeling-brief.md:64-66`："Observers …, dynamic reconfiguration, sessions/digests/payload semantics, metrics/JMX, socket timeouts as timing …, FIFO ordering of the learner channel (CR-1)." | 复述先前排除，再加上 FIFO 通道 |
| v2r1 | `modeling-brief.md:288-289`："Do not model: per-connection packet ordering (U-Scenario 3), observers, reconfiguration payloads, sessions." | 复述先前排除，再加上逐连接包序 |

### 3.3 模型结构的继承（不在文档里，但同样来自先前模型）

- **`EnterSyncPhase` 的守卫**：先前模型是 `phase[s] = "discovery" /\ phase[l] = "sync"`（`PRIOR/spec/base.tla:174`）。
  - 原样保留：v1r2（`E2/v1/r2/out/spec/base.tla:264`）、v2r2（`E2/v2/r2/out/spec/base.tla:253`）。
  - 放宽为 `phase[l] \in {"sync","broadcast"}` 或更宽：v0r1（:302）、v1r1（:309）、v2r1（:291）。
  - 改写为新动作：v0r2。其 `spec/changelog.md:31` 写 "Learners can synchronize with an established leader (removed the `phase[leader] = "sync"` guard …)"。
- **投票比较依据 `HistoryAtLeast`**：先前模型比较 `Len(durable[...])`（`PRIOR/spec/base.tla:92-95`）。
  - 原样保留：v1r2（`base.tla:153-156`）、v2r2（`base.tla:157-160`）。v2r2 在 `spec/confirmation-CR-2.md:5-6` 自述 "the stale data-tree vote is outside the model's vocabulary: votes use `durable`"；v1r2 在 `ci-report.md:14` 写 "zxid order approximated by log length; FLE votes persist across rounds"。
  - 改成 DataTree 或内存历史：v0r1 用 `LastLogged`（`changelog.md:30`："Votes … use the DataTree position"），v1r1 用 `recovered`，v2r1 用 `Len(recovered…)`。
  - 改成按 durable 的 zxid 比较：v0r2（`base.tla:147-150`）。

---

## 4. 跨 run 的缺陷机制对照（只描述）

### 4.1 机制归类

- **M1 ACK 先于 fsync**：学习者把 DIFF 或缓冲提案交给异步 SyncRequestProcessor（只入队）后就写 NEWLEADER ACK，leader 据此提交并服务历史；学习者在 fsync 前崩溃时，已服务事务丢失。
- **M2 INITIAL 失败导致内存 DB 过期并丢失数据**：学习者在 NEWLEADER 和 UPTODATE 之间失败，因 INITIAL 状态 `canShutdown()` 为假而跳过 shutdown 和 fast-forward；它用过期的 DataTree 投票或当 leader，无需崩溃即丢失已提交事务。
- **M3 INITIAL 失败导致处理器泄漏**：同一窗口下，启动的 SyncThread、CommitProcessor 等线程不被关闭，持续写日志或向已关闭的连接写 ACK。
- **M4 ACK 抢先**：SyncThread 的逐事务 ACK 先于 NEWLEADER ACK，被 LearnerHandler 当成 NEWLEADER ACK 后拒绝，导致学习者不计入 quorum，leader 无法或延迟建立 epoch。
- **M5 COMMIT 触发 NPE**：NEWLEADER 时清空了 `packetsNotCommitted`，之后到达的 COMMIT 对 `peekFirst()` 解引用，抛出 NPE，同步中止。
- **M6 TRUNC 保留多余记录**：TRUNC 的目标 zxid 不在日志中时，下一条记录被保留，学习者可能服务未提交数据。
- **M7 pre-Zab1.0 未启动**：UPTODATE-only 路径调用 `startServing()`，但没有先调用 `startupWithoutServing()`。
- **M8 先 fast-forward 后 flush**：学习者 shutdown 先 fast-forward 数据库，再 flush sync processor，日志里留下不属于 leader 历史的 ghost 提案。

### 4.2 机制 × run 矩阵

图例：

- ✓：已复现或确认（REPRODUCED）。
- △：候选或未决（NEEDS MORE INFO、DEFERRED、ENV_LIMITED）。
- ○：没有作为独立发现，只在其他发现的后果或原因里提到。
- 注：只在 brief 或排除项中作为说明出现，不是发现。
- 空：没有报告。

| 机制 | E1 v0 | E1 v1 | E1 v2 | v0r1 | v0r2 | v1r1 | v1r2 | v2r1 | v2r2 |
|---|---|---|---|---|---|---|---|---|---|
| M1 ACK 先于 fsync | △ MC-2 ENV_LIMITED | △ MC-1 ENV_LIMITED | △ MC-1 NMI | ✓ MC-1 | ✓ MC-1 | ✓ MC-1 | ✓ MC-1 | △ MC-1 DEFERRED | ✓ MC-1 |
| M2 INITIAL 失败致数据丢失 | ✓ MC-3 | ✓ MC-2 | △ MC-2 NMI | ✓ MC-2 | ○ CR-4 后果 | ✓ MC-2 | | △ MC-2 DEFERRED | ○ CR-2 后果 |
| M3 INITIAL 失败致泄漏 | ○（CR 并入 MC-3） | ○ | ○ MC-2 原因 | ○ | ✓ CR-4 | ○ MC-2 后果 | ✓ CR-2 | ○ | ✓ CR-2 |
| M4 ACK 抢先 | 注（Do not model，"liveness only"） | 注（CR-A，"Not modeled (liveness-only)"） | 注（U5，"unconfirmed hypothesis"） | △ CR-1 NMI | ✓ MC-2 | ✓ MC-3 | ✓ CR-3 | △ CR-1 NMI | ✓ CR-3 |
| M5 COMMIT 触发 NPE | ✓ MC-1 | | ✓ CR-1 | | ✓ MC-3 | | ✓ CR-1 | | |
| M6 TRUNC 保留多余记录 | | | | ✓ MC-3 | | | | | |
| M7 pre-Zab1.0 未启动 | 注（排除 `isPreZAB1_0`） | 注（brief:282） | | | ✓ CR-5 | | | | 注（§8.4 排除） |
| M8 先 fast-forward 后 flush | | 注（CR-B "Abstracted"） | △ MC-3 NMI | | | | | | |

矩阵依据：

- 各 run 的 `out/spec/final-result.json`。
- E1 v0 `modeling-brief.md:68-78`："the ACK-ordering race between SendAckRequestProcessor and the NEWLEADER ACK (liveness only)"；以及 "CR-1 … **Folded into MC-3**"。
- E1 v1 `modeling-brief.md:213-216`（CR-A、CR-B）。
- E1 v2 `modeling-brief.md:250-255`（Scenario U5）。
- v0r2 `spec/confirmation-CR-4.md:7-9`："the in-memory data tree is not fast-forwarded, so the peer votes and later leads with a stale last zxid"。
- v2r2 `final-result.json:98`："the peer's election vote uses a data tree older than its durable log (observed in a real trace)"。
- 泄漏的提及：v0r1 `bug-report.md:105`、v1r1 `final-result.json:59`、v2r1 `bug-report.md:105`。

### 4.3 出现与消失（描述性）

- **只在 epoch-2 出现，epoch-1 没有作为发现**：
  - M4：epoch-1 三个 run 都只作说明或排除；epoch-2 六个 run 都作为发现报告（4 个 ✓，2 个 △）。
  - M6：只有 v0r1。
  - M7：epoch-1 只作说明；epoch-2 只有 v0r2 作为发现。
  - M3：epoch-1 只是附带提及；epoch-2 的三个 r2 都作为独立 CR 发现。
- **在 epoch-1 出现，epoch-2 消失或变弱**：
  - M8：E1 v2 有 MC-3（△），epoch-2 六个 run 都没有提到。
  - M2：epoch-1 三个都有（2 个 ✓）；epoch-2 的 r1 三个都有（2 个 ✓，1 个 △）；r2 三个都没有作为发现，v0r2 和 v2r2 只在 CR 的后果里提到过期投票，v1r2 完全没有提到。
- **epoch-1 与 epoch-2 都有**：
  - M1：9 个 run 都有。epoch-1 全是 △；epoch-2 有 5 个 ✓、1 个 △。
  - M5：E1 v0、E1 v2、v0r2、v1r2 报告；epoch-2 的 r1 三个都没有。

---

## 5. 性质演变质量

### 5.1 先前模型的不变量与性质

`PRIOR/spec/MC.cfg` 检查 TypeOK、MCTypeOK、ElectionSafety、OneActiveLeaderPerEpoch、CommittedHistoriesPrefix、ApplyRequiresCommitCertificate、PipelinePrefix、EpochHistoryConsistency、SyncCompletionJustified，以及 PROPERTIES 中的 HistoryPositionsMonotonicExceptRecovery。各定义见 `PRIOR/spec/base.tla:517-584`。

### 5.2 各 run 对先前性质的改动

方法：用脚本按名称提取 `base.tla` 中的定义，去掉注释和空白后，与先前定义比较。

| run | 删除或改名 | 削弱 | 加强 | 先前性质中原样保留的 | 新增性质（Update 层） |
|---|---|---|---|---|---|
| v0r1 | `ApplyRequiresCommitCertificate` 改为 `ServingApplyRequiresCommitCertificate` | `OneActiveLeaderPerEpoch` 增加 `s \in leadersByEpoch[e]`；`PipelinePrefix` 去掉 `queued⊑proposed`、`snapshot⊑applied`，改为 `committed⊑proposed`（只对 active role） | `SyncCompletionJustified` 增加 `zkState[s] = "RUNNING"` | ElectionSafety、EpochHistoryConsistency、NoIllegalRollback | NewLeaderAckImpliesDurable、AckedHistoryRetained、CommittedAgreesWithQuorumHistory、LeaderCompleteness、UpdateStructural |
| v0r2 | 删除 `proposed`、`snapshot`、`recovered`、`messages` 变量 | `PipelinePrefix` 只剩 `durable⊑appended⊑queued`；`OneActiveLeaderPerEpoch` 改为 `Epoch \ {0}`、`phase ∈ {sync, broadcast}`、`currentEpoch` | MC.cfg 新增 `CommittedAgreement` | 其余 | CommittedQuorumDurable、NewLeaderAckFirst、SyncCommitHasPendingProposal、DeferredCommitMatchesPending |
| v1r1 | 无 | 无（另有探索用约束，见下） | 无 | 除 TypeOK（加变量）外全部 | NewLeaderAckImpliesDurableSync、CertifiedDurableOnQuorum、CertifiedRetainedByLaterLeaders、NewLeaderAckIsFirstAck、VotingHistoryCoversDurable |
| v1r2 | 无 | 无 | 无 | 除 TypeOK 外全部 | AckedHistoryHandedOff、NewLeaderAckDurable、CommittedSurvivesLeaderChange |
| v2r1 | 无 | Trace.cfg 不再启用 `OneActiveLeaderPerEpoch`（MC 中仍启用） | 无 | 除 TypeOK 外全部 | UpdNewLeaderAckAfterDurable、UpdEstablishedHistoryDurableOnQuorum、UpdLeaderCompleteness |
| v2r2 | 无 | 无 | 无 | 除 TypeOK（evidence 中记为 "representation-only"）外全部 | CommittedQuorumDurable、NewLeaderAckAfterLogging、CommittedNeverLostByLeader |

### 5.3 证据记录情况

- **v0 arm（v0r1、v0r2）没有 `invariant-evidence.json`**（`run.json` 中 `"invariant_evidence": null`）。改动理由只在 changelog 里用一行说明，没有 TLC 评估过的分离状态。
- **v1、v2 arm 的 4 个 run 都有 `invariant-evidence.json`**（与 `out/spec/` 下的同名文件相同）：
  - 新增性质都配有 `separating`（new 侧 TLC 结果为 false）和 `control`（true）两类证据；
  - 保留的性质都配有 `keep` 证据；
  - 所有条目的 `changed_from_initial` 都是 false；
  - 所有 `separating` 证据的 `old` 都写着 `"not checked"`，只有 v1r2 的 `E_U1_old` 是从旧语义控制中取得的状态。
- v2r1 把 liveness 列入 `unresolved`：

  > `{"property": "liveness of NEWLEADER activation when a proposal ACK precedes the NEWLEADER ACK (CR-1)", "missing_evidence": "per-connection packet order is not modeled; …"}`

### 5.4 重点例子

**A. 没有证据就削弱或删除**

1. v0r2 的 `PipelinePrefix` 少了两个子句（`queued⊑proposed`、`snapshot⊑applied`），原因是删除了 `proposed` 和 `snapshot` 变量。`spec/changelog.md` 和 `update-analysis.md` 都没有提到 PipelinePrefix 或这两个变量的删除（搜索 `proposed|snapshot|PipelinePrefix` 没有相关命中）。该 run 自己的 modeling-brief §5（`modeling-brief.md:163`，继承自先前）仍写着 "`PipelinePrefix` | Safety | Durable/appended/queued/proposed and snapshot/applied stages remain prefixes"。
2. v0r2 的 `OneActiveLeaderPerEpoch` 只有一行理由：`changelog.md:41-42` "revised to established leaders (two leaders may concurrently *propose* an epoch in DISCOVERY)"。没有给出 trace 或 TLC 证据。
3. v0r1 的三处 `[fix-inv]` 都有一行源码或 trace 理由（见 B），但没有 TLC 证据，也没有新旧对照。

**B. 把实现当前的行为写成需求（或用实现行为收窄性质）**

1. **v0r1 `PipelinePrefix`**。`spec/changelog.md:40-41`：

   > "[fix-inv] `PipelinePrefix`: log pipeline prefixes + `committed ⊑ proposed` for active roles (the role history and the txn log legitimately differ after a skipped shutdown)."

   这里被写成 "legitimately"（合法）的 "skipped shutdown"，正是同一 run 中 MC-2 的原因：`final-result.json` 的 MC-2 cause 写作 "on failure before UPTODATE, LearnerZooKeeperServer/ZooKeeperServer.shutdown return early (canShutdown), so the DataTree is not fast-forwarded"。MC-2 最终是通过新增的 `LeaderCompleteness` 发现的（`spec/findings.json:24`）。
2. **v0r1 `ApplyRequiresCommitCertificate` 改为 `ServingApplyRequiresCommitCertificate`**。`changelog.md:37-39`：

   > "restart replays every logged txn into the tree (FileTxnSnapLog.restore), so the promise only holds for a serving (RUNNING) instance."

   这是依据实现的恢复行为收窄了性质。收窄后的性质仍然抓到了 MC-3（TRUNC）：`findings.json:36`。
3. **v0r1 `OneActiveLeaderPerEpoch`**。依据真实 trace 收窄。`changelog.md:62-64`：

   > "(Case A, real trace seq 136 of attempt 3 …): a peer is LEADING before `getEpochToPropose` persists its epoch; only epoch-bound leaders (`leadersByEpoch`) are counted."

   同一现象在其他 run 中的处理方式不同：
   - v2r1 只在 Trace.cfg 中关闭该性质。`Trace.cfg` 注释："at trace granularity FLE sets role LEADING before Leader.getEpochToPropose advances the accepted epoch … It stays enabled in every MC cfg"。
   - v2r2 改的是 Trace 投影。`invariant-evidence.json` 写 "Trace projection of pre-epoch LEADING repaired (Trace.tla pendingLead)"，性质本身不变。
4. **把更新后的新行为写成性质**：
   - v1r2 的 `AckedHistoryHandedOff`，`kind` 为 "strengthening (update effect)"，证据 `E_U1_old` 的 `impl_produces` 是 "no (update) / yes (old)"。即旧版本违反、新版本满足，相当于把更新后的交付顺序写成了需求。
   - v2r2 的 `NewLeaderAckAfterLogging`，`affected_because` 为 "direct effect of the update (Learner.java:748-760)"，证据 `E2` 的 `impl_produces` 是 "no"，基础是 "updated code logs before the ACK"。
   - v1r2 的 `NewLeaderAckDurable` 和 v2r1 的 `UpdNewLeaderAckAfterDurable` 则取自源码注释中声明的意图。v1r2 写 "The update's stated contract is to sync the uncommitted logs before the NEWLEADER ACK (Learner.java:748)"，并标为 "new requirement property (update intent)"。新实现违反这类性质，所以它们不属于“当前行为即需求”。
5. **把 bug 路径写成 ghost 错误标志的不变量**：v0r2 的 `NewLeaderAckFirst == \A s : ~nlAckMisread[s]` 和 `SyncCommitHasPendingProposal == \A s : ~syncNPE[s]`，v1r1 的 `NewLeaderAckIsFirstAck == \A s : ~ackShadowed[s]`。这类性质的含义是“模型中编码的那个坏事件不发生”，是否成立取决于设置标志的动作是否忠实于实现。

**C. 用探索约束而不是改性质**：v1r1 的 MC.cfg 中，`PipelinePrefix` 被 MC-2 路径违反（`spec/output/cex/MC-2_PipelinePrefix_MCcfg.out`）。run 没有修改这个性质，而是另设 `MC-filtered.cfg`，把 `VotingHistoryCoversDurable` 用作 CONSTRAINT 来跳过已分析的路径。`MCFiltered.tla:2-6`："Exploration-only constraint; the reference behavior and the checked properties are unchanged."。`final-response.json` 也披露了："the standard round exhausted its depth-23 space only with the MC-2 class filtered"。

**D. trace 完成性质的改动**：v0r2 修改了 `TraceMatched`。`changelog.md` 的 Round 1 写道：

> "`TraceMatched` uses the existential queue-based completion property; the prior `<>(l > Len)` is universal over the silent-vote / follower-choice branches and failed on dead branches. A separate witness config (`Trace-witness.cfg`, invariant `TraceIncomplete`) records a full-consumption behavior for every trace."

改动有对应的补偿检查。

---

## 6. r1 与 r2 的差异（描述性）

### 6.1 CLI 的可用性与使用（据 `MECH` 和 timeline）

- r1 中，v0r1 和 v1r1 明确写了 CLI 不可用：
  - v0r1 `final-result.json`："The specular CLI is not installed, so ci-result reports were not generated."
  - v1r1 `final-response.json`："The specular CLI is not installed, so ci-result reports were not generated; spec/final-result.json was written."
- r2 三个 run 都调用了新 CLI：

  | run | `ci-result` 次数 | `findings` 次数 | 用法 |
  |---|---|---|---|
  | v0r2 | 6 | 2 | 先运行一次 ci-result 校验格式，`timeline.md:374` 写 "Running `specular ci-result` early to validate the final-result format (it will be re-run …)"；开局调用 `findings lookup`，`timeline.md:34` |
  | v1r2 | 2 | 3 | 开局 `findings lookup`，`timeline.md:30-31`；结束时 `timeline.md:355,359` |
  | v2r2 | 4 | 1 | 带查询条件 `lookup --query SyncWithLeaderNewLeader --query CommittedQuorumDurable …`，`timeline.md:163`；`ci-result` 在 `timeline.md:289` |

- 三个 r2 的 `persistent-findings-context.json` 都是 `"inherited_records": {}`，先前模型的 `findings.json` 本来也是 `"findings": []`，所以 lookup 没有可复用的内容。v2r2 把查询结果写进了确认文档（`spec/confirmation-CR-2.md:8`）："**Novelty**: NEW in this run's inputs (persistent findings lookup empty)."

### 6.2 形式上的变化

- r2 多出一组 CI 产物：`ci-verdict.json`、`ci-report.md`、`confirmed-bugs.md`、`bug-severity.md`、`.summary-findings.md`、`spec/persistent-findings/{index.json,<id>.json,evidence/}`。其中每条记录带 `reusable: true`、`origin_run`、`source_revision`、`sites`、`actions`、`invariants`。
- r2 每条发现都有一个 `spec/confirmation-<id>.md`，`ci-verdict.json` 的 `evidence` 字段就指向它。r1 中只有 v1r1 为每条 MC 发现写了 confirmation 文件；v0r1 用 `harness/repro/*.java` 和日志；v2r1 没有做复现。
- 状态分布：r2 全是 REPRODUCED。r1 中有 NEEDS MORE INFO（v0r1 CR-1、v2r1 CR-1）和 DEFERRED（v2r1 MC-1、MC-2）。

### 6.3 内容上的变化

- **CR 发现增多**：r1 三个 run 的 CR 数分别是 1、0、1，r2 是 2、3、2。r2 中新增的 CR 是 M3（泄漏，三个 r2 都有）、M5（v1r2）、M7（v0r2）。
- **M4 状态变化**：r1 中两个 NEEDS MORE INFO、一个 ✓；r2 中三个都是 ✓。v1r2 和 v2r2 的 M4 来源是 code-review，v0r2 的来源是 model-checking。
- **M2 消失**：见 4.3。r2 中与 M2 相关的文字只出现在 v0r2 CR-4 和 v2r2 CR-2 的后果里。三个 r2 对相应模型局限各有一句自述：
  - v0r2 `ci-report.md`："The leaked SyncThread of CR-4 is modeled only for its history effect; quiescence guards on ElectLeader and LeaderSyncFollower assume it drains before an election completes."
  - v2r2 `ci-report.md`："The stale data-tree election vote of CR-2 is not represented in the model (votes use durable history); it is evidenced by a real trace only."
  - v1r2 `ci-report.md:14`："zxid order approximated by log length; FLE votes persist across rounds"。
- **报告的严重度措辞**：
  - v0r2 MC-1 标为 Critical，其余 run 的 M1 都是 High。
  - M4 在 v0r2 中为 High，v1r1 为 Medium，v1r2 为 Medium，v2r2 为 Low。
- 是否因为 CLI 才出现这些内容变化，本文不推断。

---

## 7. 值得关注的工具或 skill 问题（只列有证据的）

1. **`ci-verdict.json` 没有总体 verdict 字段。** 三个 r2 的文件中只有 `findings[]`，"FAIL" 只出现在 `ci-report.md` 中（见 1.2）。下游如果只读 JSON，需要自己推导结论。
2. **`spec/findings.json` 与 `final-result.json` 的收录范围在不同 run 间不同。** v0r2、v1r2 的 findings.json 不含 CR，v2r2 含 CR；r1 的 findings.json 都没有 `status` 字段（见 1.3）。只按 findings.json 计数会漏掉 code-review 发现。
3. **CR 编号沿用全局编号（v0r2 的 CR-4/5、v2r2 的 CR-2/3），以及 v0r1 内部的 CR-1 与 CR-3 不一致**（`analysis-report.md:68` 对比 `bug-report.md:180`），跨 run 对照时容易出错。
4. **先前文档整体原样保留，未标明哪些是先前内容。** 例如 "No implementation bug is claimed and no property was weakened to obtain green output." 与同一文件后追加的多条 REPRODUCED 发现并存，v0r1 的 `PipelinePrefix` 也确实被削弱了（见 3.1、5.4-B1）。§6.3 "None. This fresh prior did not identify a source defect …" 也在 5/6 个 run 中原样保留。skill 没有要求把继承的段落标为“先前”，或要求重新审视这些内容。
5. **“Wall-clock liveness” 排除项被原样继承，而且没有 run 对照 scope 去审视它**；scope 中 "Liveness checks may be bounded and conditional on explicit fairness …" 也没有 run 引用（见 2.5）。同一机制（M4）在不同 run 里时而写成 safety 标志不变量，时而以 "liveness/availability … outside the safety model" 为由交给 code review（见 2.2 和 2.4），说明 skill 没有给出处理确认顺序和推进类问题的统一路径。
6. **先前模型的结构性抽象（`EnterSyncPhase` 的 `phase[l] = "sync"`、`HistoryAtLeast` 用 durable 长度）在 v1r2 和 v2r2 中原样保留，并被 run 自己引用为不建模的理由**（见 3.3）。skill 的继承审查似乎覆盖了性质，但没有覆盖这类守卫和抽象。
7. **v0 arm 没有 `invariant-evidence.json`，它的两个 run 也正是性质改动最多、证据最少的两个**（见 5.3、5.4-A）；其中 v0r1 把同一 run 中报告为 bug 原因的行为（skipped shutdown）写成了削弱性质的 "legitimately" 理由。
8. **`invariant-evidence.json` 中的 separating 证据几乎都写着 `old: "not checked"`**（见 5.3），新增性质在旧版本上的行为大多没有记录，因此无法从这份文件区分“更新引入”和“既有”。各 run 是另行用旧版本控制复现来做这个区分的。
9. **v1r1 的 `run.json` 中 `attempt_no` 为 2**，其余 run 为 1。本文没有读取第一次尝试的信息，仅作记录。
