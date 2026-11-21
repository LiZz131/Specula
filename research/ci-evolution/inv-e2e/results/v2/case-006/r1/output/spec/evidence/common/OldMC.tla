------------------------------- MODULE OldMC -------------------------------
EXTENDS OldBase

Base == INSTANCE OldBase

CONSTANTS MaxCampaignLimit, MaxProposalLimit, MaxHeartbeatLimit,
          MaxReadLimit, MaxReadyLimit, MaxQuorumCheckLimit,
          MaxCrashLimit, MaxLoseLimit, MaxMsgBufferLimit

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCInit ==
    /\ Init
    /\ faultCounters = [campaign |-> 0, proposal |-> 0,
                         heartbeat |-> 0, read |-> 0, ready |-> 0,
                         quorumCheck |-> 0, crash |-> 0, lose |-> 0]

MCCampaign(i) ==
    /\ faultCounters.campaign < MaxCampaignLimit
    /\ Base!Campaign(i)
    /\ faultCounters' = [faultCounters EXCEPT !.campaign = @ + 1]

MCClientProposal(i, v) ==
    /\ faultCounters.proposal < MaxProposalLimit
    /\ Base!ClientProposal(i, v)
    /\ faultCounters' = [faultCounters EXCEPT !.proposal = @ + 1]

MCBroadcastHeartbeat(i) ==
    /\ faultCounters.heartbeat < MaxHeartbeatLimit
    /\ Base!BroadcastHeartbeat(i)
    /\ faultCounters' = [faultCounters EXCEPT !.heartbeat = @ + 1]

MCClientReadIndex(i, c, r) ==
    /\ faultCounters.read < MaxReadLimit
    /\ Base!ClientReadIndex(i, c, r)
    /\ faultCounters' = [faultCounters EXCEPT !.read = @ + 1]

MCForwardReadIndex(i, c) ==
    /\ faultCounters.read < MaxReadLimit
    /\ Base!ForwardReadIndex(i, c)
    /\ faultCounters' = [faultCounters EXCEPT !.read = @ + 1]

MCReadyPublish(i) ==
    /\ faultCounters.ready < MaxReadyLimit
    /\ Base!ReadyPublish(i)
    /\ faultCounters' = [faultCounters EXCEPT !.ready = @ + 1]

MCCheckQuorum(i) ==
    /\ faultCounters.quorumCheck < MaxQuorumCheckLimit
    /\ Base!CheckQuorum(i)
    /\ faultCounters' = [faultCounters EXCEPT !.quorumCheck = @ + 1]

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashLimit
    /\ Base!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]

MCLoseMessage(m) ==
    /\ faultCounters.lose < MaxLoseLimit
    /\ Base!LoseMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.lose = @ + 1]

MCHandleVoteRequest(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleVoteRequest(i, m)
    /\ UNCHANGED faultVars

MCHandleVoteResponse(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleVoteResponse(i, m)
    /\ UNCHANGED faultVars

MCBecomeLeader(i) ==
    /\ Base!BecomeLeader(i)
    /\ UNCHANGED faultVars

MCHandleAppendEntries(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleAppendEntries(i, m)
    /\ UNCHANGED faultVars

MCHandleAppendResponse(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleAppendResponse(i, m)
    /\ UNCHANGED faultVars

MCHandleHeartbeat(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleHeartbeat(i, m)
    /\ UNCHANGED faultVars

MCHandleHeartbeatResponse(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleHeartbeatResponse(i, m)
    /\ UNCHANGED faultVars

MCHandleReadIndexRequest(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleReadIndexRequest(i, m)
    /\ UNCHANGED faultVars

MCHandleReadIndexResponse(i, m) ==
    /\ PublishedBySender(m)
    /\ Base!HandleReadIndexResponse(i, m)
    /\ UNCHANGED faultVars

MCReadyAdvance(i) ==
    /\ Base!ReadyAdvance(i)
    /\ UNCHANGED faultVars

MCRestart(i) ==
    /\ Base!Restart(i)
    /\ UNCHANGED faultVars

MCNext ==
    /\ Cardinality(messages) <= MaxMsgBufferLimit
    /\ \/ \E i \in Server : MCCampaign(i)
       \/ \E i \in Server, m \in messages : MCHandleVoteRequest(i, m)
       \/ \E i \in Server, m \in messages : MCHandleVoteResponse(i, m)
       \/ \E i \in Server : MCBecomeLeader(i)
       \/ \E i \in Server, v \in Values : MCClientProposal(i, v)
       \/ \E i \in Server, m \in messages : MCHandleAppendEntries(i, m)
       \/ \E i \in Server, m \in messages : MCHandleAppendResponse(i, m)
       \/ \E i \in Server : MCBroadcastHeartbeat(i)
       \/ \E i \in Server, m \in messages : MCHandleHeartbeat(i, m)
       \/ \E i \in Server, c \in ReadContexts, r \in Server :
             MCClientReadIndex(i, c, r)
       \/ \E i \in Server, c \in ReadContexts : MCForwardReadIndex(i, c)
       \/ \E i \in Server, m \in messages : MCHandleReadIndexRequest(i, m)
       \/ \E i \in Server, m \in messages : MCHandleHeartbeatResponse(i, m)
       \/ \E i \in Server, m \in messages : MCHandleReadIndexResponse(i, m)
       \/ \E i \in Server : MCReadyPublish(i)
       \/ \E i \in Server : MCReadyAdvance(i)
       \/ \E i \in Server : MCCheckQuorum(i)
       \/ \E i \in Server : MCCrash(i)
       \/ \E i \in Server : MCRestart(i)
       \/ \E m \in messages : MCLoseMessage(m)

MCSpec == MCInit /\ [][MCNext]_mcVars

\* REQ-EVIDENCE MCTypeOK
\* intent:   the base type invariant holds and every fault/budget counter stays within its configured limit.
\* status:   model-internal
\* verified: base
\* review:   ok
MCTypeOK ==
    /\ TypeOK
    /\ faultCounters \in [campaign : 0..MaxCampaignLimit,
                            proposal : 0..MaxProposalLimit,
                            heartbeat : 0..MaxHeartbeatLimit,
                            read : 0..MaxReadLimit,
                            ready : 0..MaxReadyLimit,
                            quorumCheck : 0..MaxQuorumCheckLimit,
                            crash : 0..MaxCrashLimit,
                            lose : 0..MaxLoseLimit]

StateConstraint == Cardinality(messages) <= MaxMsgBufferLimit
ModelSymmetry == Permutations(Server)
MCView == vars

\* REQ-EVIDENCE MCElectionSafety -> ElectionSafety (alias; evidence block on ElectionSafety in base.tla)
\* review:   ok
MCElectionSafety == ElectionSafety
\* REQ-EVIDENCE MCCommitWithinLog -> CommitWithinLog (alias; evidence block on CommitWithinLog in base.tla)
\* review:   ok
MCCommitWithinLog == CommitWithinLog
\* REQ-EVIDENCE MCLogMatching -> LogMatching (alias; evidence block on LogMatching in base.tla)
\* review:   ok
MCLogMatching == LogMatching
\* REQ-EVIDENCE MCCommittedPrefixAgreement -> CommittedPrefixAgreement (alias; evidence block on CommittedPrefixAgreement in base.tla)
\* review:   ok
MCCommittedPrefixAgreement == CommittedPrefixAgreement
\* REQ-EVIDENCE MCLeaderCompleteness -> LeaderCompleteness (alias; evidence block on LeaderCompleteness in base.tla)
\* review:   ok
MCLeaderCompleteness == LeaderCompleteness
\* REQ-EVIDENCE MCMessagesWellFormed -> MessagesWellFormed (alias; evidence block on MessagesWellFormed in base.tla)
\* review:   ok
MCMessagesWellFormed == MessagesWellFormed
\* REQ-EVIDENCE MCReadDeliveryJustified -> ReadDeliveryJustified (alias; evidence block on ReadDeliveryJustified in base.tla)
\* review:   ok
MCReadDeliveryJustified == ReadDeliveryJustified
\* REQ-EVIDENCE MCReadyNoInvention -> ReadyNoInvention (alias; evidence block on ReadyNoInvention in base.tla)
\* review:   ok
MCReadyNoInvention == ReadyNoInvention

\* Negated reachability claims: a violation is the expected witness.
\* REQ-EVIDENCE HuntLeader
\* intent:   reachability canary: no server has yet become leader; expected to be violated, witnessing that an election can complete.
\* status:   model-internal
\* verified: base
\* review:   ok
HuntLeader == ~scenarioSeen.leader
\* REQ-EVIDENCE HuntCommit
\* intent:   reachability canary: no leader has yet advanced its commit index; expected to be violated, witnessing that an entry can commit.
\* status:   model-internal
\* verified: base
\* review:   ok
HuntCommit == ~scenarioSeen.commit
\* REQ-EVIDENCE HuntQuorumCheck
\* intent:   reachability canary: no leader has yet run a quorum check; expected to be violated, witnessing that CheckQuorum is reachable.
\* status:   model-internal
\* verified: base
\* review:   ok
HuntQuorumCheck == ~scenarioSeen.quorumCheck
\* REQ-EVIDENCE HuntReadyRead
\* intent:   reachability canary: no Ready has yet published a read state; expected to be violated, witnessing that a read state can reach the application.
\* status:   model-internal
\* verified: base
\* review:   ok
HuntReadyRead == ~scenarioSeen.readyRead
\* REQ-EVIDENCE HuntReadResponse
\* intent:   reachability canary: no server has yet received a read-index response; expected to be violated, witnessing that the forwarded read path is reachable.
\* status:   model-internal
\* verified: base
\* review:   ok
HuntReadResponse == ~scenarioSeen.readResponse

=============================================================================
