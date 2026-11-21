# Negative controls (hand-mutated copies of fresh traces; NOT implementation traces)

- m1_quorum_read_stale_pending: record 26 claims the exact-old stale pending entry
- m2_read_reuse_readindex: record 31 second ReadState index -> 1
- m3_forwarded_resp_index: record 29 follower ReadState index -> 3
- m4_stale_ack_requester: record 35 pending.from -> s2
- m5_stale_ack_index: record 35 pending.index -> 3
