"""Extract state N of a TLC error trace log as a TLA+ conjunction (base vars only).
Usage: python3 -I tlc_state.py <log> <N> [exclude,vars]"""
import re, sys
log, n = sys.argv[1], int(sys.argv[2])
excl = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else {"counters", "seen", "l"}
text = open(log).read()
m = re.search(r'^State %d:.*?\n(.*?)(?=^State \d+:|^\d+ states generated|\Z)' % n, text, re.S | re.M)
body = m.group(1)
conj = re.split(r'\n(?=/\\ )', body.strip())
out = [c for c in conj if c.split()[1] not in excl]
print("\n".join("    " + c.replace("\n", "\n    ") for c in out))
