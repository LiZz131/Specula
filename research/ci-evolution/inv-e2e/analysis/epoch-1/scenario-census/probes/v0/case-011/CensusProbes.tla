---- MODULE CensusProbes ----
EXTENDS MC

\* Positive control: some node is Leader.
SC_PC == \E i \in Server : role[i] = "Leader"

\* A Pre-Vote response delivery that makes node i increment its vote term (the win branch, DoElect),
\* as in Update.tla PreVoteWinStep (output/spec/Update.tla:129-133).
PreWinEnabled(i) ==
    ENABLED (\E m \in messages : /\ m.kind = "PreVoteResp" /\ m.dest = i
                                 /\ MCDeliverPreVoteResponse(m)
                                 /\ vote'[i].term > vote[i].term)

\* U1: "a Candidate whose vote expired starts a Pre-Vote round (pre_elect) while its real election is
\* still collecting votes. If the real election then wins, establish_leader consumes only candidate;
\* pre_candidate survives" (output/modeling-brief.md:27-31). Precondition: established leader holding
\* a pre-candidate round it did not start as leader (same as the agent's PreVoteRoundNotInheritedByLeader).
SC_U1 ==
    \E i \in Server : preCandidateActive[i] /\ EstablishedLeader(i) /\ ~preRoundFromLeader[i]

\* U1w: "A later granting Pre-Vote response passes the runtime filter ... and handle_pre_vote_resp calls
\* elect() on the established leader" (output/modeling-brief.md:31-33).
SC_U1w ==
    \E i \in Server : EstablishedLeader(i) /\ ~preRoundFromLeader[i] /\ PreWinEnabled(i)

\* U2: "A Pre-Vote quorum must justify exactly the election it triggers" (output/modeling-brief.md:53).
\* Precondition: a Pre-Vote-triggered election (win) is enabled.
SC_U2 == \E i \in Server : PreWinEnabled(i)

\* U3: "the Pre-Vote win path (engine_impl.rs:530-541) does not [check is_voter] ... the late grant makes
\* the non-voter elect" (output/modeling-brief.md:63-71). Precondition: a Pre-Vote win is enabled on a node
\* that is not a voter of its effective config.
SC_U3 == \E i \in Server : ~InConfig(i, effectiveConfig[i]) /\ PreWinEnabled(i)

\* U4: "handle_pre_vote_req checks lease (never a transfer), last log, then vote order and changes no
\* state" (output/modeling-brief.md:76-77). Precondition: a Pre-Vote request can be handled.
SC_U4 == \E m \in messages : m.kind = "PreVoteReq" /\ ENABLED MCDeliverPreVoteRequest(m)

\* U4L: lease guard of the same scenario ("checks lease (never a transfer)", modeling-brief.md:76);
\* request handled by a node with a committed vote and a valid lease.
SC_U4L ==
    \E m \in messages :
        /\ m.kind = "PreVoteReq" /\ vote[m.dest].committed /\ leaseValid[m.dest]
        /\ ENABLED MCDeliverPreVoteRequest(m)

\* U5a: "Any accepted vote of another node (vote request grant, AppendEntries heartbeat, adopted higher
\* vote) runs become_following, which now clears pre_candidate" (output/modeling-brief.md:83-85).
SC_U5a ==
    \E i \in Server :
        /\ preCandidateActive[i]
        /\ ENABLED (\E m \in messages :
                       /\ m.dest = i
                       /\ (MCDeliverVoteRequest(m) \/ MCDeliverAppendEntries(m) \/ MCDeliverVoteResponse(m))
                       /\ ~preCandidateActive'[i])

\* U5b: "do_elect clears it (engine_impl.rs:263-264)" (output/modeling-brief.md:85-86): a direct election
\* is enabled while a pre-candidate round is alive.
SC_U5b ==
    \E i \in Server :
        /\ preCandidateActive[i]
        /\ ENABLED ((MCExternalElect(i) \/ MCStartTransferElection(i) \/ MCTickElect(i))
                    /\ candidateActive'[i] /\ ~preCandidateActive'[i])

\* U5c: "restart rebuilds the engine with pre_candidate: None (engine_impl.rs:117)"
\* (output/modeling-brief.md:86-87): a crash is enabled while a pre-candidate round is alive.
SC_U5c == \E i \in Server : preCandidateActive[i] /\ ENABLED MCCrash(i)

\* U5d: "Delayed/dropped/Unreachable Pre-Vote RPCs produce no notification ... modeled by message loss"
\* (output/modeling-brief.md:87-88).
SC_U5d ==
    \E m \in messages : m.kind \in {"PreVoteReq", "PreVoteResp"} /\ ENABLED MCDropMessage(m)
====
