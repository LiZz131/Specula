---- MODULE E3 ----
EXTENDS Update
OldV0 == INSTANCE OldBase

EInit ==
    /\ role = ("1" :> "Follower" @@ "2" :> "Follower" @@ "3" :> "Follower")
    /\ vote = ( "1" :> [term |-> 0, node |-> "1", committed |-> FALSE] @@ "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@ "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ durableVote = ( "1" :> [term |-> 0, node |-> "1", committed |-> FALSE] @@ "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@ "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ votePersistPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ replyPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ replyMessage = ( "1" :> [ lastLog |-> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE], vote |-> [term |-> 0, node |-> "1", committed |-> FALSE], kind |-> "None", dest |-> "1", source |-> "1", granted |-> FALSE, transfer |-> FALSE ] @@ "2" :> [ lastLog |-> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE], vote |-> [term |-> 0, node |-> "1", committed |-> FALSE], kind |-> "None", dest |-> "1", source |-> "1", granted |-> FALSE, transfer |-> FALSE ] @@ "3" :> [ lastLog |-> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE], vote |-> [term |-> 0, node |-> "1", committed |-> FALSE], kind |-> "None", dest |-> "1", source |-> "1", granted |-> FALSE, transfer |-> FALSE ] )
    /\ sendVotePending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaseValid = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ candidateActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ candidateVote = ( "1" :> [term |-> 0, node |-> "1", committed |-> FALSE] @@ "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@ "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ candidateConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ grants = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ sentVoteReq = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ leaderActive = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderVote = ( "1" :> [term |-> 0, node |-> "1", committed |-> FALSE] @@ "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@ "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ leaderCertified = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ leaderConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ leaderGrants = ("1" :> {} @@ "2" :> {} @@ "3" :> {})
    /\ lastLog = ( "1" :> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE] @@ "2" :> [index |-> 0, term |-> 0, node |-> "2", present |-> FALSE] @@ "3" :> [index |-> 0, term |-> 0, node |-> "3", present |-> FALSE] )
    /\ durableLastLog = ( "1" :> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE] @@ "2" :> [index |-> 0, term |-> 0, node |-> "2", present |-> FALSE] @@ "3" :> [index |-> 0, term |-> 0, node |-> "3", present |-> FALSE] )
    /\ logFlushPending = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ committedConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ committedConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ effectiveConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ effectiveConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ durableConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ durableConfigIndex = ("1" :> 0 @@ "2" :> 0 @@ "3" :> 0)
    /\ messages = { [ lastLog |-> [index |-> 0, term |-> 0, node |-> "2", present |-> FALSE], vote |-> [term |-> 1, node |-> "1", committed |-> FALSE], kind |-> "PreVoteResp", dest |-> "1", source |-> "2", granted |-> TRUE, transfer |-> FALSE ] }
    /\ crashed = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ seenGreaterLog = ("1" :> FALSE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ preCandidateActive = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ preCandidateVote = ( "1" :> [term |-> 1, node |-> "1", committed |-> FALSE] @@ "2" :> [term |-> 0, node |-> "2", committed |-> FALSE] @@ "3" :> [term |-> 0, node |-> "3", committed |-> FALSE] )
    /\ preCandidateLastLog = ( "1" :> [index |-> 0, term |-> 0, node |-> "1", present |-> FALSE] @@ "2" :> [index |-> 0, term |-> 0, node |-> "2", present |-> FALSE] @@ "3" :> [index |-> 0, term |-> 0, node |-> "3", present |-> FALSE] )
    /\ preCandidateConfig = ( "1" :> <<{"1", "2", "3"}>> @@ "2" :> <<{"1", "2", "3"}>> @@ "3" :> <<{"1", "2", "3"}>> )
    /\ preGrants = ("1" :> {"1"} @@ "2" :> {} @@ "3" :> {})
    /\ sendPreVotePending = ("1" :> TRUE @@ "2" :> FALSE @@ "3" :> FALSE)
    /\ preSentReq = ("1" :> {"2"} @@ "2" :> {} @@ "3" :> {})
    /\ preStartRole = ("1" :> "Follower" @@ "2" :> "None" @@ "3" :> "None")
    /\ faultCounters = [membership |-> 0, election |-> 0, preVote |-> 1, crash |-> 0, drop |-> 0]
    /\ PrintT(<<"E3", "old.GrantedResponseAfterDurable", OldV0!GrantedResponseAfterDurable>>)
    /\ PrintT(<<"E3", "new.GrantedResponseAfterDurable", GrantedResponseAfterDurable>>)

ENext == FALSE

ESpec == EInit /\ [][ENext]_mcVars
====
