---- MODULE TraceDbg ----
EXTENDS Trace
Dbg == (l = 152) => PrintT(<<"DBG", up["s1"], role["s1"], phase["s1"], syncMode["s1"], acceptedEpoch["s1"], currentEpoch["s1"], applied["s1"], zkState["s1"], ENABLED TPeerRoleChanged>>)
====
