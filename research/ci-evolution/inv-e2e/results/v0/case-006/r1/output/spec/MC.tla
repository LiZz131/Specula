------------------------------- MODULE MC -------------------------------
EXTENDS base

Base == INSTANCE base

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

MCElectionSafety == ElectionSafety
MCCommitWithinLog == CommitWithinLog
MCLogMatching == LogMatching
MCCommittedPrefixAgreement == CommittedPrefixAgreement
MCLeaderCompleteness == LeaderCompleteness
MCMessagesWellFormed == MessagesWellFormed
MCReadDeliveryJustified == ReadDeliveryJustified
MCReadyNoInvention == ReadyNoInvention

\* Negated reachability claims: a violation is the expected witness.
HuntLeader == ~scenarioSeen.leader
HuntCommit == ~scenarioSeen.commit
HuntQuorumCheck == ~scenarioSeen.quorumCheck
HuntReadyRead == ~scenarioSeen.readyRead
HuntReadResponse == ~scenarioSeen.readResponse

=============================================================================
