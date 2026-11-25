#!/usr/bin/env python3
"""Report final TLC expression-coverage counts for key update branches of base.tla."""
import re, sys
log, = sys.argv[1:]
base = open(__file__.rsplit('/harness/',1)[0] + '/spec/base.tla').read().splitlines()
keys = {
 "PreElect round branch (preCandidateActive' := TRUE)": r"^\s+ELSE /\\ preCandidateActive' = \[preCandidateActive EXCEPT !\[i\] = TRUE\]",
 "PreElect single-voter quorum branch (THEN DoElect)": r"^\s+THEN /\\ DoElect\(i, sgl\)",
 "HandlePreVoteRequest response": r"^\s+IN messages' = RemainingMessages\(m, consume\) \\cup \{resp\}",
 "HandlePreVoteResponseGrant (preGrants')": r"^\s+/\\ preGrants' = \[preGrants EXCEPT !\[i\] = @ \\cup \{m.source\}\]",
 "HandlePreVoteResponseElect (DoElect)": r"^\s+/\\ DoElect\(i, seenGreaterLog\[i\]\)$",
 "HandlePreVoteResponseReject (seenGreaterLog')": r"IF LogLT\(lastLog\[i\], m.lastLog\) THEN TRUE ELSE @\]",
 "HandleVoteResponse wins (leaderCertified')": r"leaderCertified' = \[leaderCertified EXCEPT !\[i\] = IF wins THEN TRUE ELSE @\]",
 "DefaultPreVoteRpcGrant (messages')": r"\{MessageR\(\"PreVoteResp\", m.dest, m.source, m.vote, NoLog\(m.dest\), TRUE, FALSE, m.vote\)\}",
 "AppendUniformConfig effective'": r"effectiveConfig' = \[effectiveConfig EXCEPT !\[i\] = <<effectiveConfig\[i\]\[2\]>>\]",
}
lines = {}
anchors = {"HandlePreVoteResponseElect (DoElect)": "HandlePreVoteResponseElect(i, m, consume) =="}
for name, rx in keys.items():
    start = 0
    if name in anchors:
        start = next(k for k, l in enumerate(base) if l.startswith(anchors[name]))
    for k, l in enumerate(base[start:], start + 1):
        if re.search(rx, l): lines.setdefault(name, k); break
txt = open(log).read()
blk = txt[txt.rfind("The coverage statistics at"):] if "The coverage statistics at" in txt else ""
for name, ln in lines.items():
    m = re.findall(r"^\s*\|*line %d, col \d+ to line \d+, col \d+ of module base: (\d+)" % ln, blk, re.M)
    print("%-55s base.tla:%-4d %s" % (name, ln, max(map(int, m)) if m else "not evaluated"))
for name in keys:
    if name not in lines: print("%-55s (pattern not found)" % name)
