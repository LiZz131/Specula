---- MODULE E7 ----
EXTENDS base
QDup == [i \in Server |-> IF i = "s1" THEN <<"ctx1", "ctx1">> ELSE <<>>]
QOk  == [i \in Server |-> IF i = "s1" THEN <<"ctx1", "ctx2">> ELSE <<>>]
UDup == INSTANCE UpdateProps WITH readQueue <- QDup
UOk  == INSTANCE UpdateProps WITH readQueue <- QOk
ASSUME PrintT(<<"E7 separating ReadQueueDistinct", UDup!ReadQueueDistinct>>)
ASSUME PrintT(<<"E7c control ReadQueueDistinct", UOk!ReadQueueDistinct>>)
Stutter == UNCHANGED vars
====
