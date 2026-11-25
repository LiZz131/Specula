"""Extract a TLC counterexample state (by l value) from a TLC log as TLA+ text."""
import re, sys
log, want_l = sys.argv[1], int(sys.argv[2])
text = open(log).read()
blocks = re.split(r'\nState \d+:[^\n]*\n', text)
for b in blocks[1:]:
    body = b.split('\n\n')[0]
    m = re.search(r'^/\\ l = (\d+)$', body, re.M)
    if m and int(m.group(1)) == want_l:
        lines = [ln for ln in body.splitlines() if not ln.startswith('/\\ l = ')]
        print('\n'.join(lines))
        sys.exit(0)
sys.exit("state with l=%d not found" % want_l)
