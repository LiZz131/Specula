# case-011 run 产物分析（epoch-2 r1/r2，附 epoch-1 r1 对照）

## 路径缩写与声明

- `E2/<arm>/<r>/` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results-epoch2/<arm>/case-011/<r>/`
- `E1/<arm>/` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results/<arm>/case-011/r1/`
- `PRIOR/` = `/users/bingzhuo/Specula/research/ci-evolution/blind-incremental-bugs/blind-incremental-v0/case-011/.specula-output/`；`PRIOR-scope` = 同级目录下的 `scope.md`
- `IN/` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/inputs/case-011/`
- `MECH` = `/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/analysis/epoch-2/mechanics.md`
- 文中 `output/...` 指 run 目录下导出的 `output/`。容器内路径分别是 `/work/current/.specula-output`（r1）和 `.specular-output`（r2）。

**未读 Gold 声明**：本分析只读了上面列出的 run 产物、公开输入、先前模型和 `MECH`。没有读、也没有检索任何 Gold、评分或答案材料，也没有读 `notes/`、`analysis/epoch-1/` 或 subjects 的 fixed 内容。下文不判断任何发现“是否真 bug”或“是否命中 Gold”，只描述 run 自己报告了什么、给了什么证据。

背景（来自 `IN/case.json`）：这次更新共改动 39 个文件，新增 `docs/protocol/pre_vote.md`、`engine/tests/handle_pre_vote_*_test.rs`、`pre_elect_test.rs`、`tests/tests/elect/t12_pre_vote.rs`，内容是 OpenRaft 的 Pre-Vote 功能。

---

## 1. 结果

### 1.1 decision 与 workflow_status

9 个 run（E1 三个、E2 r1 三个、E2 r2 三个）的 `final-response.json` 完全一致：`"decision": "MODEL_UPDATED"`，`"workflow_status": "COMPLETED_WITH_LIMITED_COVERAGE"`。E2 的 6 个 run 的 `blockers` 都是 `[]`。E1/v2 的 `blockers` 不为空，写的是：“The `specula` CLI is not installed, so `specula ci-result` ... could not be run”，以及“The Part 4 controller tool (request_bug_confirmation) is not available”。

### 1.2 发现列表（来源：各 run 的 `output/spec/final-result.json`）

| run | id | 一句话机制（据 run 自述） | status | 来源 | severity |
|---|---|---|---|---|---|
| E2/v0/r1 | MC-1 | 定时器触发的 Pre-Vote 轮次挺过 `establish_leader`，迟到的 grant 让新 Leader 调 `elect()`（debug 下 panic） | REPRODUCED | model-checking | High |
| | MC-2 | 同 term 的多个轮次共用 leader id，被成员变更移除的节点迟到的 grant 打到 `Candidate::grant_by` 的 `expect` 上，触发 panic | REPRODUCED | model-checking | Medium |
| | CR-1 | 被拒绝的 Pre-Vote 不传播更高 term，导致活多数派永久无 leader | REPRODUCED | code-review | High |
| | CR-2 | `pre_vote.md` 关于默认 `pre_vote`/Unreachable 的描述与代码不符 | NEEDS MORE INFO | code-review | Low |
| E2/v1/r1 | MC-1 | Pre-Vote 不传播更高 vote，活多数派永久无 leader（livelock） | DEFERRED | model-checking | High |
| | MC-2 | 过期的 Pre-Vote 轮次让新建立的 leader 降级 | DEFERRED | model-checking | Medium |
| E2/v2/r1 | MC-1 | 过期轮次挺过本节点赢得选举，新 Leader 调 `elect()` | REPRODUCED | model-checking | High |
| | MC-2 | 同一 probe 下更早轮次迟到的 grant，在成员变更后让 `grant_by` panic | REPRODUCED | model-checking | Medium |
| | CR-PRE-1 | 运维对当前 Leader 调 `trigger().elect()`，留下陈旧的 Leader 对象，触发 debug panic（两个版本都有） | REPRODUCED | code-review | Medium |
| | D-3 | `pre_vote.md` 与默认 `pre_vote`/Unreachable 处理不一致 | REPRODUCED | code-review | Low |
| | D-2 | Pre-Vote 达到 quorum 后，已经不是 voter 的节点仍会发起选举 | NEEDS MORE INFO | code-review | Low |
| E2/v0/r2 | MC-1 | Pre-Vote 轮次挺过 leader 建立，新 Leader 对自己重新选举，违反 `LeaderVoteCoversLocalVote` | REPRODUCED | model-checking | High |
| | CR-1 | 文档称 Unreachable 算 grant | FALSE POSITIVE | code-review | Low |
| E2/v1/r2 | MC-1 | Candidate 期间发起的轮次挺过 leader 建立，新 leader 重新选举 | REPRODUCED | model-checking | **Medium** |
| | MC-2 | 已不在当前轮 voter 集合中的节点迟到的 grant 让 RaftCore panic | REPRODUCED | model-checking | **High** |
| | CR-1 | `pre_vote.md` 向后兼容段落与传输错误语义矛盾 | FALSE POSITIVE | code-review | Low |
| E2/v2/r2 | MC-1 | 定时器轮次挺过 leader 建立，新 leader 重新选举 | REPRODUCED | model-checking | High |
| | MC-2 | 完成的轮次让已离开 voter 集合的节点 `elect()`，自投票让 RaftCore panic | REPRODUCED | model-checking | Medium |
| | MC-3 | 同一假想 vote 下重复轮次计入了被移除节点迟到的 grant，RaftCore panic | REPRODUCED | model-checking | Medium |

E1 对照：
- E1/v0：MC-1 REPRODUCED（Medium，过期轮次让新 leader 重新选举）；MC-2 REPRODUCED（Low，“Pre-Vote-triggered election skips the voter check, so a leader that removed itself starts an election”）。
- E1/v1：只有 MC-1，DEFERRED（Medium）。
- E1/v2：MC-1 REPRODUCED（High）；MC-2 REPRODUCED（Medium，“Pre-Vote responses of an earlier round are counted by a later round with the same probe; after a membership change grant_by panics”）。

### 1.3 r2 的 `ci-verdict.json` 状态分布

| run | REPRODUCED | FALSE POSITIVE | 其他 | `ci-report.md` 一行摘要 |
|---|---|---|---|---|
| E2/v0/r2 | 1（MC-1，model-checking） | 1（CR-1，code-review） | 0 | “CI verdict: **FAIL**. Reproduced bugs: 1; other unresolved findings: 0; other dispositions: 1.” |
| E2/v1/r2 | 2（MC-1、MC-2） | 1（CR-1） | 0 | “Reproduced bugs: 2; other unresolved findings: 0; other dispositions: 1.” |
| E2/v2/r2 | 3（MC-1、MC-2、MC-3） | 0 | 0 | “Reproduced bugs: 3; other unresolved findings: 0; other dispositions: 0.” |

三个 r2 都没有 DEFERRED、NEEDS MORE INFO 或 CANDIDATE 状态。

### 1.4 r2 的 `final-result.json` 与 `final-response.json` 是否一致

- **E2/v0/r2**：一致。response 写 “One real defect, MC-1 ... REPRODUCED ... CR-1 ... is documentation-only (FALSE POSITIVE). specular ci-result reports CI verdict FAIL.”，与 final-result 的两条记录和 ci-verdict 对得上。
- **E2/v1/r2**：一致，severity 也一致：response 写 “MC-1 (Medium) ... MC-2 (High) ... CR-1 ... false positive”，final-result 为 MC-1 `"severity": "Medium"`、MC-2 `"severity": "High"`。注意，这与其他 run 把 MC-1 机制定为 High 的做法不同（见第 4 节）。
- **E2/v2/r2**：发现列表一致（3 条 REPRODUCED，severity 为 High/Medium/Medium）。有一处摘要层面的差别：`final-result.json` 的 `summary` 和据此生成的 `ci-report.md` 首段写了 “A documentation mismatch about Unreachable pre-vote responses (pre_vote.md) was noted as code review only.”，但这条既不在 `findings`，也不在 `ci-verdict.json` 里；`final-response.json` 的 summary 则没有提它。它在 `output/modeling-brief.md` 里写作 CR-1，结论是 “Documentation-only inconsistency ... Recorded, not escalated.”

---

## 2. liveness 与推进性

### 2.1 是否定义了时序性质

没有 run 在模型检查中使用时序 liveness 性质（`<>`、`~>`、`WF_`/`SF_`）。在 9 个 run 的 `spec/*.tla`（不含 Trace）里 grep `~>|[]<>|<>[]|WF_|SF_|<>(`，结果为空。唯一的 `<>` 和 `WF_` 是各 run 的 `Trace.tla` 中 trace 验证用的 `TraceConsumed == <>(cursor = Len(TraceLog) + 1)`，继承自 `PRIOR/spec/Trace.tla:150-151`。所有 cfg 里的 `PROPERTIES` 都是 `[][A]_v` 形式的动作性质或 discharge 义务。

### 2.2 用 safety 写法表达推进或停滞

1. **E2/v1/r1：活锁谓词加闭包性质（唯一一例）**。`output/spec/Update.tla:180-206`：
   - `NoPermanentPreVoteLivelock == ~PreVoteLivelock`。`PreVoteLivelock` 描述的状态是：开启 Pre-Vote，存活节点构成 quorum，但每个存活 voter 的 `AttainablePreGrants(i)` 都不够 quorum。
   - `LivelockClosed == [][(PreVoteLivelock /\ LivelockStep) => PreVoteLivelock']_mcVars`。注释说 “closure is what makes the witness permanent rather than budget-limited”，即“进入该状态后，非运维、非崩溃恢复的步骤都出不去”的闭包写法。
   - 剪枝监视器 `LivelockDirector` / `LivelockDirectorPhased` 只用作 CONSTRAINT（`MC_hunt_prevote_livelock_phased.cfg`），注释写明 “pruning-only ... the absence of one proves nothing”。
   - 证据（`output/spec/evidence/livelock-results.json`）：25 步反例；从见证状态做穷尽闭包检查（`spec/witness/livelock/closure_on.log`：“9081 states generated, 1456 distinct states found, 0 states left on queue”）；对照组把 tick 换成更新前模式（`control_off.log`），结果是 “NoLiveLeader violated after 10 steps”。
   - ledger 把它记成 `"kind": "new liveness requirement encoded as a safety witness plus closure"`（`E2/v1/r1/invariant-evidence.json`）。
2. **E2/v0/r1：停滞发现走代码审查，不进模型**。CR-1 写在 `output/spec/code-review-CR-1.md`：“not a model-checking finding. The model cannot express it at the current granularity: followers never receive log entries and AppendEntries rejection/HigherVote step-down are not modeled”。证据是 5 节点集成测试 `t94` 加一个关闭 Pre-Vote 的对照（`final-result.json` 的 evidence 中有 `spec/output/repro-integration-term-stall.log`、`spec/output/repro-old-control.log`）。
3. **reachability canary（非空性，不是停滞 canary）**。每个 run 都有 `CanaryNo*`（例如 E2/v1/r1 的 `CanaryNoLeader`、E2/v2/r2 的 `CanaryNoTickRoundWhileCandidate`）。这些 canary 用来证明场景可达，不用来检测停滞。不过有一个与“推进”直接相关的副作用：先前模型的 3-voter `MC.cfg` 从来到不了 Leader。E2 的 6 个 run 都通过 canary 或 trace 发现了这一点，并修复了 `LogLE`。例如 E2/v0/r1 `spec/changelog.md` 写道：“`Canary-leader-tick-round.cfg` ... showed no Leader reachable in 3-voter configs; the immutable V0 primary config has the same property (... "no Leader" holds over all 640,830 V0 states)”。
4. **“不打断 leader”类动作性质**（safety 形式，针对 leaderless window 或 term 膨胀）：E2/v0/r1 `TickPreVoteNeverDeposesLeader`、`SelfTermIncreaseNeedsPreVoteQuorum`；E2/v1/r1 `PreVoteQuorumNeverDemotesLeader`；E2/v1/r2 `PreVoteNeverDisplacesLeader`；E2/v2/r2 `LeaderNotPreemptedByTimerPreVote`。它们都是单步性质，不涉及“最终”。
5. **deadlock**：E2/v0/r2 `spec/changelog.md` Round 4 记录，open 视图的模拟因 bounded rely 停在 deadlock，随后 “re-run with `-deadlock` (safety checks unchanged)”，理由是 “Not a property under test and impossible in full MCSpec”。

### 2.3 与推进、停滞、活锁相关的发现

| run | 发现 | 措辞 | status |
|---|---|---|---|
| E2/v0/r1 | CR-1 | “permanent leaderless stall with a live majority” | REPRODUCED（code-review） |
| E2/v1/r1 | MC-1 | “Pre-Vote can leave a live majority permanently leaderless”；bug-report 写 “Severity: High (liveness/availability ...)” | DEFERRED |
| 多个 run | MC-1（leader 被打断） | 后果里写到 leaderless window 或 term 膨胀，例如 E2/v1/r2：“leaving the cluster without a working leader for at least a lease and inflating the term” | 作为 safety 动作性质违例报告 |

E2 r2 的三个 run 和 E1 的三个 run 都没有报告永久停滞或活锁类发现。

### 2.4 run 如何说明不做 liveness（原文摘录）

- E2/v0/r1 `output/brief-coverage.md`：“No fairness or liveness claim.”，“No liveness property is model-checked.”；`validation-summary.json`：“No fairness or liveness claim from TLC”
- E2/v1/r1 `final-result.json`：“liveness is checked as a safety witness plus exhaustive closure from the witness, without fairness assumptions.”
- E2/v1/r2 `final-result.json`、`ci-report.md`：“No fairness or liveness property is claimed.”；`spec/bug-report.md:113`：“| Liveness / eventual election | — | — | Not testable: no fairness is grounded in the source; not claimed |”
- E2/v2/r1 `output/modeling-brief.md:238-239`：“No fairness is assumed; no liveness property is claimed.”；`brief-coverage.md:49`：“No liveness property is claimed (no fairness assumption is grounded in the source).”
- E2/v0/r2、E2/v2/r2：没有自己写的新声明，只有继承下来的先前文字（见第 3 节）。E2/v0/r2 的 `brief-coverage.md` 原样保留了 “No fairness or liveness guarantee is claimed.”；E2/v2/r2 的 brief 保留了 “No fairness is assumed.” 和 “Eventual election or delivery ...”。

---

## 3. 继承：先前模型里的范围说明和排除项

先前模型中与范围和排除相关的原文：

- `PRIOR-scope`（与 `IN/model-scope.md` 内容相同，run 也把它当作 `/work/model-scope.md` 拿到）：“Do not claim eventual progress unless an explicit fairness assumption is stated and grounded in the exact-old scheduler or retry behavior. Keep safety checking usable even when no fairness is selected.”；“Exclude metrics, precise timeout duration, transport framing, serialization, application payload contents, and every message or phase absent from the old tree.”
- `PRIOR/modeling-brief.md`：§1 “No fairness is assumed.”；§2 Scenario 5 “tests the principal failure model without asserting progress.”；§3.2 “Do not model”下的 “Precise milliseconds, random timeout selection, metrics, transport framing, ...” 和 “Eventual election or delivery: the exact-old code supplies retry/tick mechanisms but no unconditional scheduler, storage, or network fairness.”；§6 “This neutral prior contains no incident-derived or revision-derived findings.” / “None recorded for this neutral prior.”
- `PRIOR/analysis-report.md` “Failure and progress assumptions”：“Safety does not require fairness. Eventual election needs ticks/time advance, successful storage, scheduler execution, and enough delivered exact-vote responses, none of which is unconditional in the source.”
- `PRIOR/brief-coverage.md` “Honest limits”：“No fairness or liveness guarantee is claimed.”

逐行比对的保留情况（按非空行计算，先前文件中有多少行在 run 的同名文件里原样出现）：

| 文件 | E1/v0 | E1/v1 | E1/v2 | E2 v0 r1 | v0 r2 | v1 r1 | v1 r2 | v2 r1 | v2 r2 |
|---|---|---|---|---|---|---|---|---|---|
| modeling-brief.md（178 行） | 177 | 178 | 178 | 168 | 177 | 177 | 177 | 178 | 178 |
| analysis-report.md（151 行） | 151 | 151 | 151 | 151 | 151 | 151 | 150 | 151 | 151 |
| brief-coverage.md（32 行） | 1 | 32 | 32 | 5 | 32 | 2 | 31 | 3 | 3 |

要点：

1. **“No fairness is assumed.”、“without asserting progress”、§3.2 的 “Eventual election or delivery ... no unconditional scheduler, storage, or network fairness.” 在 9 个 run 的 `modeling-brief.md` 中全部原样保留**（grep 命中行号：E2/v0/r1 第 37/171/283-284 行，其余 run 第 15/149/172-173 行附近）。analysis-report 中的 “Safety does not require fairness. Eventual election needs ...” 也在 9 个 run 中原样保留（第 167 行）。
2. **E2/v1/r1 的内部张力**：它在同一份 brief 中保留了 §3.2 “Do not model: Eventual election or delivery ...”（第 207-208 行），同时新增了 U-S2 “Pre-Vote rejection never propagates a higher vote (liveness)” 和 `NoPermanentPreVoteLivelock`（第 298-313 行）。它用更新里新增的测试注释作为需求依据，没有改写继承来的排除项：“`tests/tests/elect/t12_pre_vote.rs:188-197` ("Pre-Vote makes elections *cautious*, not *impossible*: this is the core liveness requirement")”。
3. **E2/v0/r1** 是唯一改写了先前 brief §6 的 run：删除了 “This neutral prior contains no ... findings” 和 “None recorded for this neutral prior.” 等，换成 “The V0 prior had no findings. This run's defect ledger: ...”，所以只保留了 168/178 行。其余 E2 run（v0/r2、v1/r1、v1/r2、v2/r1、v2/r2）仍保留 “This neutral prior contains no incident-derived or revision-derived findings.” 和 “### 6.3 Code-review-only / None recorded for this neutral prior.”（例如 E2/v2/r2 `modeling-brief.md:203,217-219`），而同一 run 后面又追加了发现。
4. **近似转述**：E2/v1/r2 `bug-report.md:113` 的 “no fairness is grounded in the source” 和 E2/v2/r1 `brief-coverage.md:49` 的 “no fairness assumption is grounded in the source”，与 scope 原文 “grounded in the exact-old scheduler or retry behavior” 用的是同一个措辞框架。
5. **新排除项沿用旧排除项的写法**：E2/v1/r1 §8.5 “Pre-Vote timing (`starting_time` rate limit, `election_timeout`, ...): abstracted”；E2/v2/r1 第 300 行 “Do not model: round rate-limit timing, RPC timeouts, randomized timeouts, metrics, ...”；E2/v1/r2 第 322 行 “Do not model: precise timeouts and the in-flight-round rate limiter (time abstracted), metrics, ...”。这些都是先前“precise timeout / metrics”排除项向 Pre-Vote 新增计时字段的延伸。
6. 先前 `brief-coverage.md` 的 “Honest limits”（含 “No fairness or liveness guarantee is claimed.”）在 E2/v0/r2 和 E2/v1/r2 中整段保留（32/32、31/32）；E2 r1 三个 run 和 E2/v2/r2 重写了 brief-coverage。

---

## 4. 跨 run 的缺陷机制对照

### 4.1 机制归并

- **M1 过期 pre-candidate 挺过 leader 建立**：`establish_leader`/`become_leader` 不清理 `pre_candidate`，`handle_pre_vote_resp` 达到 quorum 后在已成为 Leader 的节点上调 `elect()`，导致 leader 被打断、term 增加，debug 构建下 `try_leader_handler` 断言 panic。
- **M2 同 probe 关联导致跨轮 grant 计数**：同一本地 vote 下的多个轮次共用 `(term+1, self)` 关联键，被成员变更移除的节点迟到的 grant 进入 `Candidate::grant_by` 的 `expect`，RaftCore panic。
- **M3 Pre-Vote quorum 后不复查 voter 身份**：`handle_pre_vote_resp` 调 `elect()` 时不重新检查 `is_voter`，已离开 voter 集合的节点仍会发起选举。后果有两种写法：term 膨胀（E1/v0），或自投票触发 `grant_by` panic（E2/v2/r2）。
- **M4 Pre-Vote 不传播更高 term，造成永久停滞**：被拒绝的 Pre-Vote 不更新本地 vote，最新日志但 term 落后的节点和 term 更高但日志较短的节点互相拒绝。
- **M5 `pre_vote.md` 与代码不一致**：文档称默认 `pre_vote` 返回 Unreachable 且 Unreachable 算 grant，代码则合成 grant，不把传输错误计为 grant。
- **M6 对当前 Leader 的运维 `trigger().elect()`**：`do_elect` 保留 Leader 对象，触发 debug panic。run 自述这是两个版本都有的既有行为。

### 4.2 机制 × run 矩阵

图例：✓ = REPRODUCED；△ = DEFERRED / NEEDS MORE INFO；FP = FALSE POSITIVE；◦ = 只在 brief 或摘要中记录，没进 findings；空白 = 没报。

| 机制 | E1/v0 | E1/v1 | E1/v2 | E2 r1 v0 | E2 r1 v1 | E2 r1 v2 | E2 r2 v0 | E2 r2 v1 | E2 r2 v2 |
|---|---|---|---|---|---|---|---|---|---|
| M1 | ✓ MC-1 (Med) | △ MC-1 (Med) | ✓ MC-1 (High) | ✓ MC-1 (High) | △ MC-2 (Med) | ✓ MC-1 (High) | ✓ MC-1 (High) | ✓ MC-1 (**Med**) | ✓ MC-1 (High) |
| M2 | | | ✓ MC-2 | ✓ MC-2 | | ✓ MC-2 | | ✓ MC-2 (**High**) | ✓ MC-3 |
| M3 | ✓ MC-2 (Low) | | | | | △ D-2 | | | ✓ MC-2 |
| M4 | | | | ✓ CR-1（code-review） | △ MC-1（model-checking） | | | | |
| M5 | ◦ | ◦ | | △ CR-2 | ◦ CR-A | ✓ D-3（code-review） | FP CR-1 | FP CR-1 | ◦ |
| M6 | | | | ◦（brief D-4 lineage） | | ✓ CR-PRE-1 | ◦（用 `AllowAdminElect = FALSE` 排除） | | |

矩阵依据：
- M5 的 ◦：E1/v0 `modeling-brief.md:123-126`；E1/v1 `modeling-brief.md:303-305`（“documentation only ... No behavioural finding.”）；E2/v1/r1 `modeling-brief.md` §8.4 “CR-A (documentation)”；E2/v2/r2 `modeling-brief.md` “Recorded, not escalated.”
- M6 的 ◦：E2/v0/r1 `modeling-brief.md:330` 写 “D-4 (lineage) ... Pre-existing mechanism, reachable before only through an operator `trigger().elect()` on a Leader”。E2/v0/r2 `Update.tla:202-204` 写 “admin triggers (trigger().elect) may elect on a Leader by design ("TODO: reject if it is already a leader?"), so cfgs checking this property set AllowAdminElect = FALSE.”

### 4.3 出现与消失（纯描述）

- **M1**：9 个 run 全部报告。只有 E1/v1 和 E2/v1/r1 是未确认状态（DEFERRED）。severity 在不同 run 之间不一致：E1/v0、E1/v1、E2/v1/r2 定为 Medium，其余定为 High。
- **M2**：E1 中只有 v2 报告；E2 中 r1 的 v0、v2 和 r2 的 v1、v2 报告（4/6）。
- **M3**：E1 只有 v0 报告（✓）；E2 只有 v2 报告（r1 为 △，r2 为 ✓）。E1/v0 和 E2/v2/r2 写的后果不同（term 膨胀 vs. panic）。
- **M4**：**只出现在 E2 r1**（v0 通过代码审查复现，v1 通过模型检查 DEFERRED）。E1 和 E2 r2 的所有 run 都没有报告。
- **M5**：在 E1 中只以 brief 备注出现；在 E2 中进入了 findings，状态各不相同（NEEDS MORE INFO / REPRODUCED / FALSE POSITIVE），另有两次只记录未列入。
- **M6**：只有 E2/v2/r1 把它列为发现。

---

## 5. 性质演变质量

### 5.1 先前性质的去留

`PRIOR/spec/MC.cfg` 有 10 条 invariant：`MCTypeOK`、`DurableVoteNotAhead`、`DurableLogNotAhead`、`VoteRequestAfterDurable`、`GrantedResponseAfterDurable`、`LeaderRoleHasCommittedSelfVote`、`CandidateRoleHasPendingSelfVote`、`MembershipAtMostOneOutstanding`、`NoForgedMessageEndpoints`、`CertifiedLeaderHasFrozenQuorum`。先前模型没有 PROPERTIES。

- **删除**：E2 的 6 个 run 都没有删除任何先前 invariant。每个 run 的 `MC.cfg` 仍启用全部 10 条（E2/v2/r2 另加了 `PreCandidateWellFormed`），每条都在 13 到 21 个 cfg 中启用。
- **定义改动**：逐条比较 `base.tla` 定义，9 条非 TypeOK 的先前 invariant 文本都没有改。只改了两处：
  1. `TypeOK`：扩展了新变量和消息类型。v1 和 v2 的 ledger 记为 weakening，并给出了 trace 状态证据，例如 E2/v2/r2 `E-TYPE-1`：“weakening justified (representation extension for a new message kind)”。
  2. 辅助算子 `LogLE`：先前定义是 `LogLE(a, b) == a = b \/ LogLT(a, b)`。6 个 run 都改成“两个 absent log 相等”（v2/r1 写成 `~a.present \/ ...`，其余写成 `LogEq`/`LogEQ`）。每个 run 都在 `base.tla` 注释里引用了代码，例如 E2/v1/r1：“`openraft/src/engine/engine_impl.rs:379 (req.last_log_id.as_ref() >= self.state.last_log_id())`”。E2/v1/r2 的 ledger 把它列为 `"decision": "modify", "kind": "weakening"`，证据 E6 是一条实现 trace：“traces/pre_vote_req_grant_empty_logs.ndjson (response_granted=true with both logs absent)”。由于 `DurableLogNotAhead` 使用 `LogLE`，这一改动间接改变了它的语义；只有 E2/v1/r2 在 ledger 中注明：“Helper LogLE repaired ...; the property compares a node's own logs, whose placeholders coincide”。
- **ledger 覆盖缺口**（性质本身仍启用，但没有逐条记录）：
  - E2/v1/r1 的 ledger 没有 `DurableLogNotAhead`、`MembershipAtMostOneOutstanding`、`NoForgedMessageEndpoints`，也没有 `LogLE`（R-5）。
  - E2/v1/r2 没有 `MembershipAtMostOneOutstanding`，也没有过滤变体 `PreVoteElectionPremiseCurrentNonLeader`。
  - E2/v2/r1 把三条放进 `unaffected_properties`，但没记 `LogLE`。
  - E2/v2/r2 没有 `DurableVoteNotAhead`、`DurableLogNotAhead`、`MembershipAtMostOneOutstanding`、`CertifiedLeaderHasFrozenQuorum`、`LogLE`。
  - v0 arm 的两个 run 没有 `invariant-evidence.json`；改动只记在 `spec/changelog.md` 中。

### 5.2 新增性质（只计非 canary、非 discharge）

| run | 新增 |
|---|---|
| E2/v0/r1 | `TickPreVoteNeverDeposesLeader`、`SelfTermIncreaseNeedsPreVoteQuorum`、`PreVoteRequestIsReadOnly`、`PreElectLeavesVoteUnchanged`、`PreVoteProbeIsNextTerm`、`PreVoteTrackerWellFormed` |
| E2/v0/r2 | `LeaderVoteCoversLocalVote`、`PreCandidateTracksNextTerm`、`PreVoteStepIsSideEffectFree` |
| E2/v1/r1 | `PreCandidateProbesNextTerm`、`PreVoteQuorumNeverDemotesLeader`、`NoPermanentPreVoteLivelock`（+`LivelockClosed`） |
| E2/v1/r2 | `PreVoteElectionPremiseCurrent`（+NonLeader 过滤变体）、`PreVoteNeverDisplacesLeader`、`EstablishedLeaderHasNoInheritedPreVote`、`PreCandidateTermUnbumped`、`PreVoteMessagesWellFormed`、`PreVoteGrantFromRoundMember`、`NoPanicOnStalePreVoteGrant` |
| E2/v2/r1 | `PreVoteRoundNotOutlivedByOwnLeadership`、`PreVoteElectionByVoter`、`PreVoteElectionAtProbedVote`、`PreVoteRequestIsPure`、`PreVoteStartIsPure`、`PreVoteGrantFromTrackedVoter`、`LeaderObjectVoteNotBehind` |
| E2/v2/r2 | `PreCandidateWellFormed`、`TickPreVoteRoundNotHeldByLeader`、`LeaderNotPreemptedByTimerPreVote`、`PreVoteGrantsWithinFrozenVoters`、`CandidateGrantsWithinFrozenVoters`、`PreVoteElectionAtProbedVote`、`PreVoteStepsDoNotPersist` |

### 5.3 “把实现当前行为写成需求”的例子

1. **“Pre-Vote 不改变本地 vote”被写成需求，同时又被别的 run 当作停滞发现的成因**：
   - E2/v2/r2 `Update.tla:199-211` 的 `PreVoteStepsDoNotPersist`。intent 为 “handling a Pre-Vote request or a **non-deciding Pre-Vote response** changes no vote ...”，状态是 `status: requirement`。证据是文档 `pre_vote.md:42-44`，以及本次更新新增的单元测试 `handle_pre_vote_resp_test.rs:88 test_handle_pre_vote_resp_reject_keeps_waiting "assert_eq!(vote_before, *eng.state.vote_ref());" -> a rejected response changes no vote`。ledger 的 `E-P6` 记为 “strengthening justified”，用模型变异 MUT-A 证明可证伪。
   - 同类性质还有：E2/v0/r2 `PreVoteStepIsSideEffectFree`（只覆盖发出 PreVoteReq/PreVoteResp 的步骤）；E2/v2/r1 `PreVoteRequestIsPure`、`PreVoteStartIsPure`（证据为 `pre_vote.md:42-45`、`raft/mod.rs:939-940` 和更新新增的 `pre_elect_test.rs`）；E2/v0/r1 `PreVoteRequestIsReadOnly`、`PreElectLeavesVoteUnchanged`。
   - 对照：E2/v0/r1 CR-1 把 “`Engine::handle_pre_vote_resp` never updates the local vote ... comment "A Pre-Vote response never updates the local vote"” 列为永久停滞的成因；E2/v1/r1 MC-1 也写 “handle_pre_vote_resp ignores a rejecting responder's higher vote”。E2/v1/r1 还指出文档与代码不一致：“the documented responder rule is "lease, then log, *otherwise it would grant*" ... whereas the code additionally rejects a Pre-Vote whose vote is below the responder's (`engine_impl.rs:441-446`)”。
   - 也就是说，同一实现行为在 E2/v2/r2 中被固化为需求，证据包括更新自带的测试；在 E2/v0/r1、E2/v1/r1 中被当作缺陷成因。E2 r2 的三个 run 都没有报告 M4。
2. **用实现里的 TODO 把运维路径排除出性质**：E2/v0/r2 的 `LeaderVoteCoversLocalVote` 只在 `AllowAdminElect = FALSE` 下检查，依据是代码注释 “"TODO: reject if it is already a leader?"”，并写成 “may elect on a Leader by design”。E2/v2/r1 把同一路径报成 CR-PRE-1（REPRODUCED，“panics (both revisions)”）。
3. **缺少非实现证据时的处理（没有削弱，而是标成 unresolved）**：E2/v2/r1 `PreVoteElectionByVoter` 的 ledger 写 `"ledger_status": "unknown"`、`unresolved: "missing_evidence": "non-implementation evidence that a non-voter must not start an election, or that it may"`，证据引用写 `raft_core.rs:1971-1974 (impl guard only)`。`final-result.json` 写 “it was disabled in the continued hunts after its counterexamples were recorded”，对应发现 D-2 的状态是 NEEDS MORE INFO。E2/v2/r2 把同一机制（M3）直接写成需求 `CandidateGrantsWithinFrozenVoters`（`"ledger_status": "requirement"`），并以 panic 为后果报告 MC-2。
4. **已知反例的过滤变体**：E2/v1/r2 `PreVoteElectionPremiseCurrentNonLeader`（“Known-counterexample filter (MC-1 is the Leader case)”）、E2/v2/r1 的 `*_filtered.cfg`、E2/v0/r1 的 `Update-full-noU2*.cfg`，都是在已有反例记录后，为继续搜索而排除已知情形。这些变体只在 changelog 或 cfg 注释中说明，ledger 中没有对应条目（E2/v1/r2）。

### 5.4 遇到违例后改模型的情况（均给出了证据）

- E2/v0/r1 `Restart` 修复：起因是 `MC_hunt_prevote_membership.cfg` 的反例，被归为 Case B，修复后清除旧实例的 Pre-Vote 消息。依据是 “RPC responses only reach the RaftCore that issued the request (`spawn_parallel_vote_requests` sends on that core's `tx_notification`)”，并保留了修复前的日志。
- E2/v0/r2 的 EnvUpdate rely 加强：起因是 open 视图中 `DurableLogNotAhead` 违例，修复依据为 “Real omitted context (leader-only append) appends under the current vote”，标注 “Case B for the open view (rely too weak), not a finding”。
- E2/v2/r2 把 `PreVoteResponseFromFrozenVoter` 改成 `PreVoteGrantsWithinFrozenVoters`：`"change_reason": "the repaired-model control CTRL-D-voter-recheck-repeat showed the in-flight form also rejects a legal state ... moved to the point of counting"`。

在本 case 的 E2 run 里，没有发现“没有证据就删除或削弱先前 invariant”的情况。

---

## 6. r1 与 r2 的差异（描述性）

1. **CLI 使用**（`MECH` 与 timeline）：
   - r2 三个 run 都在复现确认前调用了 `specular findings ... lookup`：E2/v0/r2 `timeline.md` [231]、E2/v1/r2 [211]、E2/v2/r2 [337-338]。三份 `persistent-findings-context.json` 都是 `"inherited_records": {}`，先前模型没有发现可供继承。
   - r2 三个 run 都运行了 `specular ci-result`。E2/v0/r2 和 E2/v1/r2 先“dry-run”一次以检查格式（v0 [371]：“dry-running `specular ci-result` to surface format errors early”；v1 [444]：“Running `specular ci-result` early to catch any contract errors”），最后再跑一次。E2/v1/r2 中间修正了一个失效的 evidence 路径（[540]：“One evidence path moved when I archived the pre-repair runs”）。
   - r1：E2/v1/r1 和 E2/v2/r1 都执行了 `which specular specula`（v1 [361]，v2 [77]）。E2/v2/r1 的 `analysis-report.md:384` 写 “the `specular` CLI is not installed in this environment”，final-response 写 “specular ci-result and the reproduction controller were not available, so final-result.json was written but not rendered”。E2/v0/r1 没有相关调用。
2. **产物形式**：r2 多了 `ci-report.md`、`ci-verdict.json`、`confirmed-bugs.md`、`bug-severity.md`、`persistent-findings-context.json`、`spec/persistent-findings/{index.json,<ID>.json,evidence/}`，且每个发现都有 `spec/confirmation-<ID>.md`。r2 的 MC 发现在 `final-result.json` 中带 `persistence` 块（`sites`、`actions`、`invariants`、`premises`、`dependencies`，后者含 start/end 锚点）；r1 的 `final-result.json` 没有这个块。r1 的确认材料命名不统一：E2/v0/r1 用 `reproduction-MC-2.md`、`code-review-CR-1.md`，E2/v2/r1 用 `code-review-findings.md`，E2/v1/r1 没有确认材料。
3. **状态集合**：r2 的所有发现都是 REPRODUCED 或 FALSE POSITIVE。r1 中有 DEFERRED（E2/v1/r1 两条）、NEEDS MORE INFO（E2/v0/r1 CR-2、E2/v2/r1 D-2），以及代码审查来源的 REPRODUCED（E2/v0/r1 CR-1、E2/v2/r1 CR-PRE-1、D-3）。
4. **内容差别**：
   - r2 的代码审查条目只有文档不一致（M5），其中两个 run 定为 FALSE POSITIVE，一个只记录未列入。r1 的代码审查条目包括 M4（停滞）、M5、M6、M3（D-2）。
   - r2 中所有 REPRODUCED 发现都来自模型检查。
   - r1 的 v1 arm 没有执行复现（DEFERRED），r2 的 v1 arm 复现了两条。
   - 本节只记录这些差别，不推断原因。

---

## 7. 值得关注的工具或 skill 问题（只列有证据的）

1. **r1 布局下 CLI 不可用**：E1/v2 的 `blockers` 写 “The `specula` CLI is not installed ... `specula ci-result` ... could not be run”，以及 “The Part 4 controller tool (request_bug_confirmation) is not available”。E2/v2/r1 也写 “specular ci-result and the reproduction controller were not available”。E2/v1/r1 的 Part 4 未执行（“Part 4 reproduction not executed in this run”），两条发现停在 DEFERRED。
2. **先前模型的空性缺陷被继承**：先前 `LogLE` 让 3-voter `MC.cfg` 无法选出 leader。E2/v0/r1 写 “"no Leader" holds over all 640,830 V0 states”，E2/v1/r2 写 “the prior suite's three-voter MC results were vacuous for leader paths”，6 个 E2 run 都各自修复了它。先前 `PRIOR/brief-coverage.md` 的非空性证据写的是 “leader-role implications reached 152,826 leader-node evaluations, and frozen-quorum implications reached 118,452 certified-leader-node evaluations in the membership companion run”，原文没有单独说明 3-voter 主配置能否到达 Leader。先前 suite 没有给 3-voter 主配置做 leader 可达性 canary。
3. **继承的 brief 文本没有更新**：5 个 E2 run 在追加发现的同时，保留了先前 brief §6 的 “This neutral prior contains no incident-derived or revision-derived findings.” 和 “None recorded for this neutral prior.”（见第 3 节第 3 点）。E2/v1/r1 同时保留了 “Do not model: Eventual election” 并新增了 liveness 编码性质。
4. **invariant-evidence ledger 覆盖不全**：v1 和 v2 arm 的 4 个 run 都有未列入 ledger 的先前 invariant 或辅助算子改动（`LogLE`），也有未列入的过滤变体（见 5.1 和 5.3 第 4 点）。v0 arm 不产生 ledger。
5. **MCP 和执行环境**：
   - E2/v0/r2 `changelog.md` 记录 “VAV clean on base.tla (run on a copy with tuple-literal aliases stubbed because the VAV tool rejects them)”，`MECH` 中对应 `mcp__spec_analyzer__run_vav_analysis` 报错 1 次（E2/v1/r2 也有 1 次）。
   - 同一 changelog 记录 “Four batch-1 runs were killed by the agent tool's 10-minute background limit (`*-interrupted.log`); all were re-run”。
   - 工具链：E2 r1 三个 run 都记录 “nightly-2026-03-01, which is not installed (`/opt/rustup` read-only)”，改用 stable 1.100.0。E2/v0/r2 的 analysis-report 写 “the requested `nightly-2026-03-01` is now installed and was used”。
6. **`final-result.summary` 与 findings 不一致**：E2/v2/r2 的 summary 和 `ci-report.md` 提到了文档不一致，但 `findings` 和 `ci-verdict.json` 中没有这条（见 1.4）。`ci-result` 原样采用 summary，没有做一致性检查。
7. **`MECH` 中 L1/L2/L3 三列对 case-011 的 6 个 run 都是 “-”**，本报告没有额外信息可以补充。
