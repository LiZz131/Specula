---- MODULE E1_old ----
EXTENDS MC
\* state source: output/mc-upd-full-cws-final.log State 11; edits: none
EvInit ==
    /\ witnessIndex = (n1 :> -1 @@ n2 :> 1 @@ n3 :> -1)
    /\ messages = {}
    /\ voteCommitted = (n1 :> TRUE @@ n2 :> TRUE @@ n3 :> TRUE)
    /\ witnessConfig = (n1 :> {{n1, n2, n3}} @@ n2 :> {{n1, n3}, {n1, n2, n3}} @@ n3 :> {{n1, n2, n3}})
    /\ witnessNodes = (n1 :> {} @@ n2 :> {n2, n3} @@ n3 :> {})
    /\ witnessTerm = (n1 :> 0 @@ n2 :> 1 @@ n3 :> 0)
    /\ effectiveMembershipIndex = (n1 :> -1 @@ n2 :> 1 @@ n3 :> 1)
    /\ effectiveConfig = ( n1 :> {{n1, n2, n3}} @@
      n2 :> {{n1, n3}, {n1, n2, n3}} @@
      n3 :> {{n1, n3}, {n1, n2, n3}} )
    /\ effectiveMembershipTerm = (n1 :> 0 @@ n2 :> 1 @@ n3 :> 1)
    /\ membershipChanges = 1
    /\ electionActions = 1
    /\ matchedTerm = ( n1 :> (n1 :> 0 @@ n2 :> 0 @@ n3 :> 0) @@
      n2 :> (n1 :> 1 @@ n2 :> 1 @@ n3 :> 1) @@
      n3 :> (n1 :> 0 @@ n2 :> 0 @@ n3 :> 0) )
    /\ losses = 0
    /\ committedMembershipIndex = (n1 :> -1 @@ n2 :> 1 @@ n3 :> -1)
    /\ lastLog = (n1 :> 0 @@ n2 :> 1 @@ n3 :> 1)
    /\ logTerm = ( n1 :> (0 :> 1 @@ 1 :> 0) @@
      n2 :> (0 :> 1 @@ 1 :> 1) @@
      n3 :> (0 :> 1 @@ 1 :> 1) )
    /\ crashed = {}
    /\ currentTerm = (n1 :> 1 @@ n2 :> 1 @@ n3 :> 1)
    /\ committed = (n1 :> -1 @@ n2 :> 1 @@ n3 :> 0)
    /\ crashes = 0
    /\ matchedIndex = ( n1 :> (n1 :> -1 @@ n2 :> -1 @@ n3 :> -1) @@
      n2 :> (n1 :> 0 @@ n2 :> 1 @@ n3 :> 1) @@
      n3 :> (n1 :> -1 @@ n2 :> -1 @@ n3 :> -1) )
    /\ clientAppends = 1
    /\ role = (n1 :> "follower" @@ n2 :> "leader" @@ n3 :> "follower")
    /\ voteFor = (n1 :> n2 @@ n2 :> n2 @@ n3 :> n2)
    /\ committedConfig = (n1 :> {{n1, n2, n3}} @@ n2 :> {{n1, n3}, {n1, n2, n3}} @@ n3 :> {{n1, n2, n3}})
    /\ voteGranted = (n1 :> {} @@ n2 :> {n1, n2} @@ n3 :> {})
    /\ committedMembershipTerm = (n1 :> 0 @@ n2 :> 1 @@ n3 :> 0)
    /\ PrintT(<<"EVAL", "E1", "old", <<"CommitWitnessSound", CommitWitnessSound>>, <<"CommittedLogAgreement", CommittedLogAgreement>>, <<"MembershipOrder", MembershipOrder>>, <<"OneOutstandingMembership", OneOutstandingMembership>>, <<"ElectionSafety", ElectionSafety>>, <<"CommitWithinLocalLog", CommitWithinLocalLog>>>>)
EvNext == UNCHANGED <<vars, electionActions, clientAppends, membershipChanges, crashes, losses>>
====
