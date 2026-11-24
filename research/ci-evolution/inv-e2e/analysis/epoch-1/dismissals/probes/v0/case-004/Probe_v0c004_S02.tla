---- MODULE Probe_v0c004_S02 ----
\* Dismissal (modeling-brief.md:81-83): "A failed transfer leaves follower leases disabled
\* until the vote changes ... Liveness/availability only; the model's lease abstraction
\* already admits every acceptance."
\* Canary: a follower keeps a disabled lease while its committed vote still names a live
\* leader of the same vote and no candidate exists (the transfer did not produce a leader).
EXTENDS Update
Canary == \E f \in Server :
            /\ up[f] /\ ~leaseEnabled[f] /\ voteCommitted[f]
            /\ \E l \in Server \ {f} :
                 /\ l = voteNode[f] /\ up[l] /\ leader[l]
                 /\ voteTerm[l] = voteTerm[f] /\ voteNode[l] = l
            /\ \A c \in Server : ~candidate[c]
NotCanary == ~Canary
====
