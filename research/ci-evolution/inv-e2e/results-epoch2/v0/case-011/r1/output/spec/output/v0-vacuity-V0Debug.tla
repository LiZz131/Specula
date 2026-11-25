---- MODULE V0Debug ----
EXTENDS MC
NoLeaderV0 == ~\E i \in Server : role[i] = "Leader"
====
