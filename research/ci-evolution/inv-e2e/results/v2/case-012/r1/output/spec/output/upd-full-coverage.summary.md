# Action coverage probe (Update_full.cfg, BFS, 240 s, -coverage 3)

Log: `spec/output/upd-full-coverage.log` (last coverage report; distinct:total successor counts).

| MC action | distinct | total |
|---|---:|---:|
| MCStartElection | 6013 | 63203 |
| MCGrantVote | 4458 | 14407 |
| MCClientAppend | 6479 | 42795 |
| MCProposeMembership | 10113 | 59857 |
| MCSendAppendEntries | 42614 | 216031 |
| MCDeliverAppendEntries (MC.tla:96) | 38243 | 138806 |
| MCRejectAppendConflict (MC.tla:97) | 0 | 0 |
| MCHandleUpdateMatched (MC.tla:98) | 24734 | 54365 |
| MCDiscardNegativeAck (MC.tla:99) | 0 | 0 |
| MCLoseMessage (MC.tla:100) | 42848 | 230700 |
| MCCrash | 169251 | 181734 |
| MCRecover | 53214 | 62193 |

Conflict rejection / negative-ack discard remain without positive coverage at the explored depths (same limitation as V0; in V1 leader progress restarts at None after every election, so the first AppendEntries of a leadership carries prev = None, which is always accepted). Recorded as LIMITED_COVERAGE.
