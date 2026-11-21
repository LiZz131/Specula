import re, sys
text = open(sys.argv[1]).read()
start = text.find('Error: The behavior up to this point is:')
body = text[start:]
states = re.split(r'\n(?=State \d+: )', body)[1:]
prev = {}
keep = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
for st in states:
    lines = st.split('\n')
    header = lines[0]
    vars_ = {}
    cur = None
    for ln in lines[1:]:
        m = re.match(r'^/\\ (\w+) = (.*)$', ln)
        if m:
            cur = m.group(1); vars_[cur] = m.group(2)
        elif cur and ln.strip() and not ln.startswith('State') and not ln.startswith('Error') and not ln.startswith('Progress') and not ln[0].isdigit():
            vars_[cur] += ' ' + ln.strip()
        else:
            if ln.strip()=='' : cur=None
    print(header)
    for k, v in vars_.items():
        if keep and k not in keep: continue
        if prev.get(k) != v:
            print('   %s = %s' % (k, v[:400]))
    prev = vars_
