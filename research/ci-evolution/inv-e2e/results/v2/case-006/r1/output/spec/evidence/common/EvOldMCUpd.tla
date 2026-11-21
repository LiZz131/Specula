---------------------------- MODULE EvOldMCUpd ----------------------------
(* Evidence E4: explore the exact-old (V0) MC model and evaluate the update
   structural property UpdReadStateOnlyAtLeader (reads role, readQueue and
   pendingReads[i][c].active only). *)
EXTENDS OldMC
U == INSTANCE Update WITH readStamp <- 0, servedReads <- {}
EvUpdReadStateOnlyAtLeader == U!UpdReadStateOnlyAtLeader
=============================================================================
