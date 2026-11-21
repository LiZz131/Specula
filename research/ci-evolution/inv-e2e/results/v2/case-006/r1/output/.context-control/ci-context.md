# CI context (run-local working memory) — case-006

- Source: artifact HEAD c780d355 (update) over 7289d1c5 (baseline). Diff: read_only.go:103 delete key
  req.Context -> req.Entries[0].Data; raft_test.go adds TestRaftFreesReadOnlyMem.
- Disposition (Ch.1 complete): MODEL_CHANGE_REQUIRED. Released contexts now leave pendingReadIndex;
  V0 kept them active (stale). Changes enablement of addRequest dedup (re-registration of a completed
  ctx in same leader term now possible) and recvAck for late acks.
- Key risk derived: ctx reuse after completion + delayed old-round MsgHeartbeatResp (same term, same ctx)
  acks the NEW pending instance -> read index not confirmed after registration -> stale read possible
  if a newer-term leader committed meanwhile. Old code: second request never registered (liveness loss only).
- Repairs of V0 defects needed for update verification: (R1) raft.reset() recreates readOnly on
  becomeFollower/Candidate/Leader (raft.go:489-511); V0 never cleared read state on role change.
  (R2) V0 HandleReadIndexResponse took evidence from leader's live pending map (only worked with stale
  entries) -> use servedReads history. (R3) HandleReadIndexResponse term handling (Step raft.go:679-735).
- Build: build/gopath (+gopath-old) GOPATH overlay; build/work-source (copy @update), build/old-work-source (@baseline).

## Progress (03:38Z)
- Generation done: base.tla (update + R1-R3 + ghosts), Trace.tla/TraceUpd.tla, Update.tla (+U3Next directed hunt), cfgs, brief/report, invariant-evidence.json (E1-E4, K1-K2, R1 all TLC-evaluated).
- Validation done: harness v2 (run.sh/validate.sh/repro.sh), 6 fresh traces pass with TraceMatched; old-model replay rejects at release & step-down; 5 mutants rejected.
- Repro: update tree stale read (ReadState idx 2 after idx 3 committed in term 2); baseline no stale read but reuse never answered.
- MC batch1: MC.cfg exhaustive no violation (4.29M distinct, depth 31; VIEW excludes counters -> limited); complete_core exhaustive; UpdReadAckFresh violated in focused (depth 19) + stale-ack hunt (depth 21-22); focused cex ADMITTED by full MCNext (spec/admit/); upd_full BFS budget-limited depth 21 no violation (VIEW/ordering limit).
- Note: TLC stopAfter prints "Model checking completed" — use states-left-on-queue to classify LIMITED.
- Pending: batch2a (linearizable bfs+sim), batch2 (open, discharge, forwarded, directed U3, full sim, inherited hunts/canaries); then bug-report.md, findings.json, final-result.json, validation-report MC section, final regression check, final JSON.
- DONE (04:3xZ): all parts complete; final-response.json written.
