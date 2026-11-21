"""Generate one-state TLC evidence modules: old (V0) vs new property verdicts."""
import os
VARS = ["up","role","phase","leaderOf","acceptedEpoch","currentEpoch","votes","leadersByEpoch",
        "proposed","queued","appended","durable","committed","applied","snapshot","acked",
        "commitCertified","messages","syncMode","syncSource","syncJustified","usedTxn",
        "rollbackAuthorized","epochSet","syncBuf","syncCommits","syncStarted","pending","nlAckSent","nlAcks","zkState"]
DEFAULT = {
 "up":"[s \\in Server |-> TRUE]", "role":'[s \\in Server |-> "looking"]', "phase":'[s \\in Server |-> "election"]',
 "leaderOf":"[s \\in Server |-> Nil]", "acceptedEpoch":"[s \\in Server |-> 1]", "currentEpoch":"[s \\in Server |-> 1]",
 "votes":"[s \\in Server |-> {s}]", "leadersByEpoch":"[e \\in Epoch |-> IF e = 1 THEN {s1} ELSE {}]",
 "proposed":"[s \\in Server |-> H]", "queued":"[s \\in Server |-> H]", "appended":"[s \\in Server |-> H]",
 "durable":"[s \\in Server |-> H]", "committed":"[s \\in Server |-> H]", "applied":"[s \\in Server |-> H]",
 "snapshot":"[s \\in Server |-> <<>>]", "acked":"[t \\in Txn |-> Server]", "commitCertified":"[t \\in Txn |-> t \\in TxnIds(H)]",
 "messages":"{}", "syncMode":'[s \\in Server |-> "NONE"]', "syncSource":"[s \\in Server |-> Nil]",
 "syncJustified":"[s \\in Server |-> FALSE]", "usedTxn":"TxnIds(H)", "rollbackAuthorized":"[s \\in Server |-> FALSE]",
 "epochSet":"[s \\in Server |-> FALSE]", "syncBuf":"[s \\in Server |-> <<>>]", "syncCommits":"[s \\in Server |-> <<>>]",
 "syncStarted":"[s \\in Server |-> FALSE]", "pending":"[s \\in Server |-> <<>>]", "nlAckSent":"[s \\in Server |-> FALSE]", "nlAcks":"[s \\in Server |-> {}]",
 "zkState":'[s \\in Server |-> "NONE"]'}
CASES = {
 # strengthening witness: broadcast follower without NEWLEADER ACK
 "E-SCJ": dict(desc="follower s2 in broadcast with syncJustified but no NEWLEADER ACK", over={
   "role":'[s \\in Server |-> IF s = s1 THEN "leading" ELSE IF s = s2 THEN "following" ELSE "looking"]',
   "phase":'[s \\in Server |-> IF s \\in {s1, s2} THEN "broadcast" ELSE "election"]',
   "leaderOf":"[s \\in Server |-> IF s \\in {s1, s2} THEN s1 ELSE Nil]",
   "syncJustified":"[s \\in Server |-> s = s2]", "epochSet":"[s \\in Server |-> s \\in {s1, s2}]",
   "zkState":'[s \\in Server |-> IF s \\in {s1, s2} THEN "RUNNING" ELSE "NONE"]'},
   props=["SyncCompletionJustified"]),
 "E-SCJc": dict(desc="control (legal): same follower after its NEWLEADER ACK", over={
   "role":'[s \\in Server |-> IF s = s1 THEN "leading" ELSE IF s = s2 THEN "following" ELSE "looking"]',
   "phase":'[s \\in Server |-> IF s \\in {s1, s2} THEN "broadcast" ELSE "election"]',
   "leaderOf":"[s \\in Server |-> IF s \\in {s1, s2} THEN s1 ELSE Nil]",
   "syncJustified":"[s \\in Server |-> s = s2]", "nlAckSent":"[s \\in Server |-> s = s2]",
   "epochSet":"[s \\in Server |-> s \\in {s1, s2}]",
   "zkState":'[s \\in Server |-> IF s \\in {s1, s2} THEN "RUNNING" ELSE "NONE"]'},
   props=["SyncCompletionJustified"]),
 "E-SACc": dict(desc="control (must stay forbidden): RUNNING server serving an uncommitted record", over={
   "applied":"[s \\in Server |-> IF s = s2 THEN Append(H, EntryFor(t2, 1)) ELSE H]",
   "proposed":"[s \\in Server |-> IF s = s2 THEN Append(H, EntryFor(t2, 1)) ELSE H]",
   "queued":"[s \\in Server |-> IF s = s2 THEN Append(H, EntryFor(t2, 1)) ELSE H]",
   "zkState":'[s \\in Server |-> IF s = s2 THEN "RUNNING" ELSE "NONE"]', "usedTxn":"{t1, t2}"},
   props=["ApplyRequiresCommitCertificate:ServingApplyCommitted"]),
 "E-OALc": dict(desc="control (must stay forbidden): two established leaders in epoch 1", over={
   "role":'[s \\in Server |-> IF s \\in {s1, s2} THEN "leading" ELSE "looking"]',
   "epochSet":"[s \\in Server |-> s \\in {s1, s2}]",
   "leadersByEpoch":"[e \\in Epoch |-> IF e = 1 THEN {s1, s2} ELSE {}]"},
   props=["OneActiveLeaderPerEpoch"]),
 "E-PPc": dict(desc="control (must stay forbidden): live server whose snapshot is not a prefix of its data tree", over={
   "snapshot":"[s \\in Server |-> IF s = s2 THEN <<EntryFor(t2, 1)>> ELSE <<>>]", "usedTxn":"{t1, t2}"},
   props=["PipelinePrefix"]),
 "E-A2": dict(desc="constructed separating state: active leader s2 (epoch 2) lacks certified t1", over={
   "role":'[s \\in Server |-> IF s = s2 THEN "leading" ELSE "looking"]',
   "acceptedEpoch":"[s \\in Server |-> 2]", "currentEpoch":"[s \\in Server |-> 2]",
   "leadersByEpoch":"[e \\in Epoch |-> IF e = 1 THEN {s1} ELSE IF e = 2 THEN {s2} ELSE {}]",
   "epochSet":"[s \\in Server |-> s = s2]",
   "committed":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]",
   "applied":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]",
   "proposed":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]","queued":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]",
   "appended":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]","durable":"[s \\in Server |-> IF s = s2 THEN <<>> ELSE H]",
   "zkState":'[s \\in Server |-> IF s = s2 THEN "RUNNING" ELSE "NONE"]'},
   props=["-:LeaderCompleteness"]),
 "E-A2c": dict(desc="control (legal): active leader s1 (epoch 2) holding certified t1", over={
   "role":'[s \\in Server |-> IF s = s1 THEN "leading" ELSE "looking"]',
   "acceptedEpoch":"[s \\in Server |-> 2]", "currentEpoch":"[s \\in Server |-> 2]",
   "leadersByEpoch":"[e \\in Epoch |-> IF e \\in {1, 2} THEN {s1} ELSE {}]",
   "epochSet":"[s \\in Server |-> s = s1]",
   "zkState":'[s \\in Server |-> IF s = s1 THEN "RUNNING" ELSE "NONE"]'},
   props=["-:LeaderCompleteness", "-:CommittedPersistedOnQuorum"]),
 "E-A1c": dict(desc="control (must stay forbidden): active leader whose committed t1 is persisted only on itself", over={
   "role":'[s \\in Server |-> IF s = s1 THEN "leading" ELSE "looking"]',
   "acceptedEpoch":"[s \\in Server |-> 2]", "currentEpoch":"[s \\in Server |-> 2]",
   "leadersByEpoch":"[e \\in Epoch |-> IF e \\in {1, 2} THEN {s1} ELSE {}]",
   "epochSet":"[s \\in Server |-> s = s1]",
   "committed":"[s \\in Server |-> IF s = s1 THEN H ELSE <<>>]","applied":"[s \\in Server |-> IF s = s1 THEN H ELSE <<>>]",
   "durable":"[s \\in Server |-> IF s = s1 THEN H ELSE <<>>]","appended":"[s \\in Server |-> IF s = s1 THEN H ELSE <<>>]",
   "queued":"[s \\in Server |-> H]","proposed":"[s \\in Server |-> H]",
   "zkState":'[s \\in Server |-> IF s = s1 THEN "RUNNING" ELSE "NONE"]'},
   props=["-:CommittedPersistedOnQuorum"]),
}
root = "evidence"
for cid, c in CASES.items():
    d = os.path.join(root, cid); os.makedirs(d, exist_ok=True)
    name = cid.replace("-", "_")
    st = dict(DEFAULT); st.update(c["over"])
    init = "\n".join(f"    /\\ {v} = {st[v]}" for v in VARS)
    reports = []
    for p in c["props"]:
        old, new = p.split(":") if ":" in p else (p, p)
        oldv = "\"not-checked\"" if old == "-" else f"Old!{old}"
        reports.append(f'<<"{p}", {oldv}, {new}>>')
    mod = f"""---- MODULE {name} ----
(* {c['desc']} *)
EXTENDS UpdateProps
CONSTANTS s1, s2, s3, t1, t2
Old == INSTANCE OldBase WITH recovered <- applied
H == <<EntryFor(t1, 1)>>
EvInit ==
{init}
EvNext == UNCHANGED allVars
EvSpec == EvInit /\\ [][EvNext]_allVars
Report == PrintT(<<"{cid}", {", ".join(reports)}>>)
====
"""
    open(os.path.join(d, name + ".tla"), "w").write(mod)
    cfg = f"""SPECIFICATION EvSpec
CONSTANTS
    Server = {{s1, s2, s3}}
    Txn = {{t1, t2}}
    MaxEpoch = 3
    Nil = Nil
    t1 = t1
    t2 = t2
    s1 = s1
    s2 = s2
    s3 = s3
CHECK_DEADLOCK FALSE
INVARIANTS
    Report
"""
    open(os.path.join(d, name + ".cfg"), "w").write(cfg)
print("generated", list(CASES))
