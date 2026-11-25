---- MODULE W_livelock ----
\* Init = last state (25) of output/mc-hunt-livelock-phased-bfs.log
EXTENDS Update
WInit ==
    /\ appendBehindVote = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ candidateActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> TRUE)
    /\ candidateConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ candidateVote = ( "1" :> [committed |-> FALSE, node |-> "1", term |-> 1] @@
         "2" :> [committed |-> FALSE, node |-> "2", term |-> 0] @@
         "3" :> [committed |-> FALSE, node |-> "3", term |-> 2] )
    /\ committedConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ committedConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ crashed = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ durableConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ durableConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ durableLastLog = ( "1" :> [node |-> "1", index |-> 0, term |-> 0, present |-> FALSE] @@
         "2" :> [node |-> "2", index |-> 0, term |-> 0, present |-> FALSE] @@
         "3" :> [node |-> "3", index |-> 0, term |-> 0, present |-> FALSE] )
    /\ durableVote = ( "1" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@
         "2" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@
         "3" :> [committed |-> FALSE, node |-> "3", term |-> 2] )
    /\ effectiveConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ effectiveConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ grants = ("1" :> {"1", "3"} @@ "2" :> {} @@ "3" :> {"3"})
    /\ lastLog = ( "1" :> [node |-> "1", index |-> 1, term |-> 1, present |-> TRUE] @@
         "2" :> [node |-> "1", index |-> 1, term |-> 1, present |-> TRUE] @@
         "3" :> [node |-> "3", index |-> 0, term |-> 0, present |-> FALSE] )
    /\ leaderActive = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderCertified = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ leaderGrants = ("1" :> {"1", "3"} @@ "2" :> {} @@ "3" :> {})
    /\ leaderVote = ( "1" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@
         "2" :> [committed |-> FALSE, node |-> "2", term |-> 0] @@
         "3" :> [committed |-> FALSE, node |-> "3", term |-> 0] )
    /\ leaseValid = ("1" :> TRUE @@ "2" :> TRUE @@ "3" :> FALSE)
    /\ logFlushPending = ("1" :> TRUE @@ "2" :> TRUE @@ "3" :> FALSE)
    /\ messages = { [ vote |-> [committed |-> FALSE, node |-> "1", term |-> 1],
           lastLog |-> [node |-> "1", index |-> 0, term |-> 0, present |-> FALSE],
           kind |-> "PreVoteReq",
           dest |-> "3",
           source |-> "1",
           granted |-> FALSE,
           round |-> [committed |-> FALSE, node |-> "1", term |-> 1],
           transfer |-> FALSE ],
         [ vote |-> [committed |-> FALSE, node |-> "3", term |-> 2],
           lastLog |-> [node |-> "3", index |-> 0, term |-> 0, present |-> FALSE],
           kind |-> "PreVoteReq",
           dest |-> "1",
           source |-> "3",
           granted |-> FALSE,
           round |-> [committed |-> FALSE, node |-> "3", term |-> 2],
           transfer |-> FALSE ],
         [ vote |-> [committed |-> FALSE, node |-> "3", term |-> 2],
           lastLog |-> [node |-> "3", index |-> 0, term |-> 0, present |-> FALSE],
           kind |-> "VoteReq",
           dest |-> "1",
           source |-> "3",
           granted |-> FALSE,
           round |-> [committed |-> FALSE, node |-> "3", term |-> 2],
           transfer |-> FALSE ] }
    /\ preActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ preConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ preGrants = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ preVote = ( "1" :> [committed |-> FALSE, node |-> "1", term |-> 1] @@
         "2" :> [committed |-> FALSE, node |-> "2", term |-> 0] @@
         "3" :> [committed |-> FALSE, node |-> "3", term |-> 2] )
    /\ replyMessage = ( "1" :>
             [ vote |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               lastLog |-> [node |-> "1", index |-> 0, term |-> 0, present |-> FALSE],
               kind |-> "None",
               dest |-> "1",
               source |-> "1",
               granted |-> FALSE,
               round |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               transfer |-> FALSE ] @@
         "2" :>
             [ vote |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               lastLog |-> [node |-> "1", index |-> 0, term |-> 0, present |-> FALSE],
               kind |-> "None",
               dest |-> "1",
               source |-> "1",
               granted |-> FALSE,
               round |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               transfer |-> FALSE ] @@
         "3" :>
             [ vote |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               lastLog |-> [node |-> "1", index |-> 0, term |-> 0, present |-> FALSE],
               kind |-> "None",
               dest |-> "1",
               source |-> "1",
               granted |-> FALSE,
               round |-> [committed |-> FALSE, node |-> "1", term |-> 0],
               transfer |-> FALSE ] )
    /\ replyPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ role = ("1" :> "Leader" @@ "2" :> "Follower" @@ "3" :> "Candidate")
    /\ seenGreaterLog = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> TRUE)
    /\ sendVotePending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ sentVoteReq = ("1" :> {"3"} @@ "2" :> {} @@ "3" :> {"1", "2"})
    /\ vote = ( "1" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@
         "2" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@
         "3" :> [committed |-> FALSE, node |-> "3", term |-> 2] )
    /\ votePersistPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ faultCounters = [election |-> 0, external |-> 0, membership |-> 0, crash |-> 0, restart |-> 0, drop |-> 0]
WSpec == WInit /\ [][MCNext]_mcVars
WVote == [i \in Server |-> (( "1" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@   "2" :> [committed |-> TRUE, node |-> "1", term |-> 1] @@   "3" :> [committed |-> FALSE, node |-> "3", term |-> 2] ))[i]]
VotesFrozen == \A i \in LiveSet : vote[i] = WVote[i]
NoLiveLeader == \A i \in LiveSet : role[i] /= "Leader"
====
