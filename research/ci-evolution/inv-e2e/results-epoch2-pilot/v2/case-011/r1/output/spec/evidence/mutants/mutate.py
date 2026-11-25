import sys
mid, path = sys.argv[1], sys.argv[2]
s = open(path).read()
M = {
 # Pre-Vote handled like a real vote on grant: the responder adopts the vote.
 "M-U1-prevote-req-adopts-vote": ('''       IN messages' = RemainingMessages(m, consume) \\cup
             {PreMessage("PreVoteResp", i, m.source, m.vote, lastLog[i], grant, m.round)}
    /\\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>''',
 '''       IN /\\ messages' = RemainingMessages(m, consume) \\cup
             {PreMessage("PreVoteResp", i, m.source, m.vote, lastLog[i], grant, m.round)}
          /\\ vote' = [vote EXCEPT ![i] = IF grant THEN m.vote ELSE @]
    /\\ UNCHANGED <<runtimeVars, durableVote, votePersistPending, replyPending, replyMessage,
                    sendVotePending, leaseValid, candidateVars, leaderVars, logVars,
                    configVars, preVars>>'''),
 # pre_elect bumps the local term like elect() (without SaveVote).
 "M-U2-pre-elect-bumps-term": ('''            /\\ GreaterLogAfter(i, resetGreater)
            /\\ UNCHANGED <<role, crashed, voteVars, candidateVars, leaderVars,
                            logVars, configVars, messages>>''',
 '''            /\\ GreaterLogAfter(i, resetGreater)
            /\\ vote' = [vote EXCEPT ![i] = Vote(vote[i].term + 1, i, FALSE)]
            /\\ UNCHANGED <<role, crashed, durableVote, votePersistPending, replyPending,
                            replyMessage, sendVotePending, leaseValid, candidateVars, leaderVars,
                            logVars, configVars, messages>>'''),
 # The pre-vote asks about term+2 (election then runs at term+1).
 "M-U3-elect-skips-term": ('''            /\\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = Vote(vote[i].term + 1, i, FALSE)]''',
 '''            /\\ preCandidateVote' = [preCandidateVote EXCEPT ![i] = Vote(vote[i].term + 2, i, FALSE)]'''),
 # Old become_following(): granting a real vote does not drop the pre-candidate.
 "M-U7-follow-keeps-precandidate": ('''       /\\ preCandidateActive' = [preCandidateActive EXCEPT ![i] = IF follows THEN FALSE ELSE @]
       /\\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\\ nv.committed /\\ nv.node = i''',
 '''       /\\ UNCHANGED preCandidateActive
       /\\ leaderActive' = [leaderActive EXCEPT ![i] = IF follows THEN FALSE
                                                      ELSE IF grant /\\ nv.committed /\\ nv.node = i'''),
}
a, b = M[mid]
if s.count(a) != 1:
    sys.exit(1)
open(path, 'w').write(s.replace(a, b))
