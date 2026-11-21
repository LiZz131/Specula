------------------------------- MODULE MC -------------------------------
EXTENDS base

CONSTANTS MaxStarts, MaxClientProposals, MaxCrashes

VARIABLES starts, clientProposals, crashes

mcvars == <<vars, starts, clientProposals, crashes>>

MCInit ==
    /\ Init
    /\ starts = 0
    /\ clientProposals = 0
    /\ crashes = 0

MCNormal ==
    /\ NormalNext
    /\ UNCHANGED <<starts, clientProposals, crashes>>

MCStart ==
    /\ starts < MaxStarts
    /\ \E i \in Server : StartServer(i)
    /\ starts' = starts + 1
    /\ UNCHANGED <<clientProposals, crashes>>

MCClientProposal ==
    /\ clientProposals < MaxClientProposals
    /\ \E l \in Server, t \in Txn : Propose(l, t)
    /\ clientProposals' = clientProposals + 1
    /\ UNCHANGED <<starts, crashes>>

MCCrash ==
    /\ crashes < MaxCrashes
    /\ \E i \in Server : Crash(i)
    /\ crashes' = crashes + 1
    /\ UNCHANGED <<starts, clientProposals>>

MCNext == MCNormal \/ MCStart \/ MCClientProposal \/ MCCrash

MCSpec == MCInit /\ [][MCNext]_mcvars

MCTypeOK ==
    /\ TypeOK
    /\ starts \in 0..MaxStarts
    /\ clientProposals \in 0..MaxClientProposals
    /\ crashes \in 0..MaxCrashes

MCStateConstraint ==
    /\ Cardinality(globalCommitted) <= MaxClientProposals
    /\ Cardinality(broadcastReady) <= Cardinality(Server)

=============================================================================
