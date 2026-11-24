---- MODULE CensusProbes ----
EXTENDS Update
\* Census probes for v2/case-011 (state predicates only; no actions).

\* PC (positive control): some Pre-Vote round was started (MC counter).
SC_PC == faultCounters.prevote > 0

\* U1a. "pre_elect installs only pre_candidate and queues SendPreVote" (output/modeling-brief.md:271)
\* / PreVoteRoundPersistsNothing "starting a Pre-Vote round without self quorum" (spec/UpdateProps.tla:128)
SC_U1a == \E i \in Server : preCandidateActive[i]

\* U1b. "handle_pre_vote_req answers with the lease/log/vote rules of a real vote but mutates nothing"
\* (output/modeling-brief.md:271-272). Encoded: a Pre-Vote response produced by a responder's handler
\* (not a synthesized fallback grant) exists.
SC_U1b == \E m \in messages : m.kind = "PreVoteResp" /\ m.source \notin PreVoteFallbackPeers

\* U1c. PreVoteRoundPersistsNothing "... and handling a non-deciding Pre-Vote response change no vote ..."
\* (spec/UpdateProps.tla:128). Encoded: a correlated Pre-Vote response is pending whose handling would
\* not reach the quorum (a rejection, or a grant that does not complete the quorum).
SC_U1c == \E m \in messages :
            /\ m.kind = "PreVoteResp"
            /\ preCandidateActive[m.dest] /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
            /\ \/ ~m.granted
               \/ /\ m.source \in ConfigVoters(preCandidateConfig[m.dest])
                  /\ ~IsQuorum(preCandidateConfig[m.dest], preGrants[m.dest] \cup {m.source})

\* U2a. "A timer Pre-Vote round outlives the node's own leader establishment ... If the original election
\* then wins, establish_leader / become_leader do not clear pre_candidate" (output/modeling-brief.md:279,283-284)
SC_U2a == \E i \in Server : role[i] = "Leader" /\ preCandidateActive[i] /\ preCandidateByTimer[i]

\* U2b. "Late Pre-Vote grants ... pass the leader-id correlation (raft_core.rs:1815-1816) and
\* handle_pre_vote_resp calls elect() ... on the established Leader" (output/modeling-brief.md:285-287)
\* Encoded: U2a plus a correlated grant from a member that completes the Pre-Vote quorum is pending.
SC_U2b == \E i \in Server : \E m \in messages :
            /\ role[i] = "Leader" /\ preCandidateActive[i] /\ preCandidateByTimer[i]
            /\ m.kind = "PreVoteResp" /\ m.dest = i /\ m.granted
            /\ SameLeaderId(m.vote, preCandidateVote[i])
            /\ m.source \in ConfigVoters(preCandidateConfig[i])
            /\ IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})

\* U3. "Scenario U3: Pre-Vote quorum hands over to the unchanged real election ... the quorum calls elect()"
\* (output/modeling-brief.md:296-297). Encoded: a correlated member grant that completes the quorum is pending.
SC_U3 == \E m \in messages :
            /\ m.kind = "PreVoteResp" /\ m.granted
            /\ preCandidateActive[m.dest] /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
            /\ m.source \in ConfigVoters(preCandidateConfig[m.dest])
            /\ IsQuorum(preCandidateConfig[m.dest], preGrants[m.dest] \cup {m.source})

\* U4a. "An earlier round's grants therefore count toward the current round." (output/modeling-brief.md:308-309)
\* Encoded: a granted response of an earlier round, correlated by probed leader id, is pending.
SC_U4a == \E m \in messages :
            /\ m.kind = "PreVoteResp" /\ m.granted
            /\ preCandidateActive[m.dest] /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
            /\ m.round /= preRound[m.dest]

\* U4b. "If the membership changed between the rounds, a stale grant from a node outside the new frozen
\* quorum set reaches grant_by, which expects membership and panics" (output/modeling-brief.md:309-311)
SC_U4b == \E m \in messages :
            /\ m.kind = "PreVoteResp" /\ m.granted
            /\ preCandidateActive[m.dest] /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
            /\ m.round /= preRound[m.dest]
            /\ m.source \notin ConfigVoters(preCandidateConfig[m.dest])

\* U5a. "enable_pre_vote is an AtomicBool toggled at runtime ... so a timer can take either branch"
\* (output/modeling-brief.md:316-317). Encoded (weaker: which branch earlier timers took is not kept in
\* state): both timer branches are enabled in the cfg and a timer Pre-Vote round is active.
SC_U5a == TickPreVoteModes = {FALSE, TRUE} /\ \E i \in Server : preCandidateActive[i] /\ preCandidateByTimer[i]

\* U5b. "a network without pre_vote synthesizes a grant (network/v2/network.rs:158-161)"
\* (output/modeling-brief.md:317-318)
SC_U5b == \E m \in messages : m.kind = "PreVoteResp" /\ m.source \in PreVoteFallbackPeers

\* U6a. "granting another node's vote, accepting AppendEntries from another leader, adopting a higher vote ...
\* drop the round; a stale response then is ignored" (output/modeling-brief.md:322-324)
\* Encoded: a node that had a round, has no pre-candidate now, is alive, and a Pre-Vote response to it is pending.
SC_U6a == \E m \in messages : m.kind = "PreVoteResp" /\ ~crashed[m.dest]
                             /\ ~preCandidateActive[m.dest] /\ preRound[m.dest] > 0

\* U6b. "Cancellation paths and crash/restart of a Pre-Vote round ... restart ... drop the round"
\* (output/modeling-brief.md:321-323). Encoded (weaker: the crash counter is global): after the crash budget
\* was used, every node is up again and some node that had a round has no pre-candidate.
SC_U6b == faultCounters.crash > 0 /\ (\A j \in Server : ~crashed[j])
          /\ \E i \in Server : preRound[i] > 0 /\ ~preCandidateActive[i]
====
