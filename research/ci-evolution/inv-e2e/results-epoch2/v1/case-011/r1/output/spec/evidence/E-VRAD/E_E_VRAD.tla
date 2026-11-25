---- MODULE E_E_VRAD ----
EXTENDS Update, TLC
OldB == INSTANCE OldBase
FC0 == [election |-> 0, external |-> 0, membership |-> 0, crash |-> 0, restart |-> 0, drop |-> 0]
S ==
    /\ appendBehindVote = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ candidateActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ candidateConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ candidateVote = ( "1" :> [term |-> 1, node |-> "2", committed |-> TRUE] @@
         "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@
         "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ committedConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ committedConfigIndex = ("1" :> 1 @@ "2" :> 0 @@ "3" :> 0)
    /\ crashed = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ durableConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ durableConfigIndex = ("1" :> 1 @@ "2" :> 0 @@ "3" :> 0)
    /\ durableLastLog = ( "1" :> [term |-> 1, node |-> "1", present |-> TRUE, index |-> 1] @@
         "2" :> [term |-> 0, node |-> "2", present |-> FALSE, index |-> 0] @@
         "3" :> [term |-> 0, node |-> "3", present |-> FALSE, index |-> 0] )
    /\ durableVote = ( "1" :> [term |-> 1, node |-> "2", committed |-> TRUE] @@
         "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@
         "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ effectiveConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ effectiveConfigIndex = ("1" :> 1 @@ "2" :> 0 @@ "3" :> 0)
    /\ grants = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ lastLog = ( "1" :> [term |-> 1, node |-> "1", present |-> TRUE, index |-> 1] @@
         "2" :> [term |-> 0, node |-> "2", present |-> FALSE, index |-> 0] @@
         "3" :> [term |-> 0, node |-> "3", present |-> FALSE, index |-> 0] )
    /\ leaderActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderCertified = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ leaderGrants = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ leaderVote = ( "1" :> [term |-> 1, node |-> "2", committed |-> TRUE] @@
         "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@
         "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ leaseValid = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ logFlushPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ messages = { [ vote |-> [term |-> 2, node |-> "1", committed |-> FALSE],
           lastLog |-> [term |-> 1, node |-> "1", present |-> TRUE, index |-> 1],
           kind |-> "PreVoteReq",
           source |-> "1",
           granted |-> FALSE,
           dest |-> "2",
           transfer |-> FALSE,
           round |-> [term |-> 2, node |-> "1", committed |-> FALSE] ],
         [ vote |-> [term |-> 2, node |-> "1", committed |-> FALSE],
           lastLog |-> [term |-> 1, node |-> "1", present |-> TRUE, index |-> 1],
           kind |-> "PreVoteReq",
           source |-> "1",
           granted |-> FALSE,
           dest |-> "3",
           transfer |-> FALSE,
           round |-> [term |-> 2, node |-> "1", committed |-> FALSE] ] }
    /\ preActive = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ preConfig = ( "1" :> <<{"1", "2", "3"}>> @@
         "2" :> <<{"1", "2", "3"}>> @@
         "3" :> <<{"1", "2", "3"}>> )
    /\ preGrants = ("1" :> {"1"} @@ "2" :> {} @@ "3" :> {})
    /\ preVote = ( "1" :> [term |-> 2, node |-> "1", committed |-> FALSE] @@
         "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@
         "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ replyMessage = ( "1" :>
             [ vote |-> [term |-> 0, node |-> "1", committed |-> FALSE],
               lastLog |-> [term |-> 0, node |-> "1", present |-> FALSE, index |-> 0],
               kind |-> "None",
               source |-> "1",
               granted |-> FALSE,
               dest |-> "1",
               transfer |-> FALSE,
               round |-> [term |-> 0, node |-> "1", committed |-> FALSE] ] @@
         "2" :>
             [ vote |-> [term |-> 0, node |-> "1", committed |-> FALSE],
               lastLog |-> [term |-> 0, node |-> "1", present |-> FALSE, index |-> 0],
               kind |-> "None",
               source |-> "1",
               granted |-> FALSE,
               dest |-> "1",
               transfer |-> FALSE,
               round |-> [term |-> 0, node |-> "1", committed |-> FALSE] ] @@
         "3" :>
             [ vote |-> [term |-> 0, node |-> "1", committed |-> FALSE],
               lastLog |-> [term |-> 0, node |-> "1", present |-> FALSE, index |-> 0],
               kind |-> "None",
               source |-> "1",
               granted |-> FALSE,
               dest |-> "1",
               transfer |-> FALSE,
               round |-> [term |-> 0, node |-> "1", committed |-> FALSE] ] )
    /\ replyPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ role = ("1" :> "Follower" @@ "2" :> "Follower" @@ "3" :> "Follower")
    /\ seenGreaterLog = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ sendVotePending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ sentVoteReq = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ vote = ( "1" :> [term |-> 1, node |-> "2", committed |-> TRUE] @@
         "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@
         "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ votePersistPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ faultCounters = FC0
ESpec == S /\ [][UNCHANGED mcVars]_mcVars
PreVoteReqAboveDurable == \E m \in messages : m.kind = "PreVoteReq" /\ VoteLT(durableVote[m.source], m.vote)
ExtendedToPreVote == \A m \in messages : m.kind \in {"VoteReq", "PreVoteReq"} => VoteLE(m.vote, durableVote[m.source])
Report == PrintT(<<"E-VRAD", "records", PreVoteReqAboveDurable, "old", OldB!VoteRequestAfterDurable, "new", VoteRequestAfterDurable, "extended", ExtendedToPreVote>>)

====
