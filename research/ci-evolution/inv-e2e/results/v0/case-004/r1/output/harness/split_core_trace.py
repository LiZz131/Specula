#!/usr/bin/env python3
"""Split a raw RaftCore hook trace into replayable per-node chains.

Input: NDJSON written by openraft/src/specula_core_trace.rs; every event carries the Engine
`pre` state and post `state` of one real handler call (post is null for VoteResponsePanic).

Output: one file per maximal chain of consecutive events of the same node whose pre-state equals
the previous post-state (all fields except `commands`, which records only commands emitted by the
handler). Each output file starts with a `Bootstrap` event holding the chain's first pre-state.
Chains therefore never assume unrecorded transitions; any unrecorded Engine input on that node
(append-entries, notifications, ticks, ...) starts a new chain.

Node identities are renamed for the model, whose `NoNode` is 0: a real node id k becomes k+1;
a (term, node) pair with term 0 is the default leader id and maps to NoNode (0).

Usage: split_core_trace.py RAW OUT_DIR PREFIX
Prints an inventory line per chain and a summary; exits non-zero if RAW has no events.
"""
import json
import os
import sys


def m(x):
    return x + 1


def map_term_node(term, node):
    return 0 if term == 0 else m(node)


def map_state(st):
    if st is None:
        return None
    s = dict(st)
    s["node_id"] = m(st["node_id"])
    s["vote_node"] = map_term_node(st["vote_term"], st["vote_node"])
    s["last_seen_node"] = map_term_node(st["last_seen_term"], st["last_seen_node"])
    s["logs"] = [dict(x, node=map_term_node(x["term"], x["node"])) for x in st["logs"]]
    s["effective_configs"] = [[m(v) for v in c] for c in st["effective_configs"]]
    s["learners"] = [m(v) for v in st["learners"]]
    s["granters"] = [m(v) for v in st["granters"]]
    s["matches"] = [dict(x, peer=m(x["peer"])) for x in st["matches"]]
    return s


def map_args(name, a):
    a = dict(a)
    if name == "TransferLeader":
        a["from_node"] = map_term_node(a["from_term"], a["from_node"])
        a["to"] = m(a["to"])
    elif name == "VoteRequest":
        a["candidate"] = map_term_node(a["term"], a["candidate"])
        a["last_node"] = map_term_node(a["last_term"], a["last_node"])
    elif name in ("VoteResponse", "VoteResponsePanic"):
        a["peer"] = m(a["peer"])
        a["owner"] = map_term_node(a["term"], a["owner"])
    return a


def strip(st):
    return {k: v for k, v in st.items() if k != "commands"}


def main():
    raw, out_dir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    events = []
    with open(raw) as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    if not events:
        print(f"ERROR: no events in {raw}")
        return 2

    chains = {}  # node -> list of chains (list of events)
    for e in events:
        ev = e["event"]
        node = ev["node"]
        cl = chains.setdefault(node, [])
        cur = cl[-1] if cl else None
        if (
            cur is not None
            and cur[-1]["event"]["state"] is not None
            and strip(cur[-1]["event"]["state"]) == strip(ev["pre"])
        ):
            cur.append(e)
        else:
            cl.append([e])

    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for node in sorted(chains):
        for k, chain in enumerate(chains[node]):
            first = chain[0]["event"]
            if first["pre"]["last_index"] < 0:
                names = ",".join(c["event"]["name"] for c in chain)
                print(f"SKIP {prefix}-n{node}-c{k}: empty-log pre-state (no index-0 entry) events={names}")
                continue
            boot_state = map_state(first["pre"])
            boot_state["commands"] = []
            lines = [{"tag": "trace", "ts": chain[0]["ts"],
                      "event": {"name": "Bootstrap", "node": m(node), "args": {}, "state": boot_state}}]
            for c in chain:
                ev = c["event"]
                st = map_state(ev["state"]) if ev["state"] is not None else map_state(ev["pre"])
                lines.append({"tag": "trace", "ts": c["ts"],
                              "event": {"name": ev["name"], "node": m(node),
                                        "args": map_args(ev["name"], ev["args"]), "state": st}})
            path = os.path.join(out_dir, f"{prefix}-n{node}-c{k}.ndjson")
            with open(path, "w") as f:
                for x in lines:
                    f.write(json.dumps(x, separators=(",", ":")) + "\n")
            written += 1
            names = ",".join(c["event"]["name"] for c in chain)
            print(f"CHAIN {os.path.basename(path)} real_node={node} events={len(chain)} [{names}]")
    print(f"SUMMARY raw_events={len(events)} chains_written={written}")
    return 0 if written > 0 else 3


if __name__ == "__main__":
    sys.exit(main())
