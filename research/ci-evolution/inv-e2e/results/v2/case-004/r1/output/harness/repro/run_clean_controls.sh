#!/usr/bin/env bash
# Clean-tree reproduction/controls for MC-1 (no Specula instrumentation).
#  - update   (d7176ef): repro (expected FAIL: learner panics) + guarded control (expected PASS)
#  - baseline (d86101c): guarded control only (Raft::transfer_leader does not exist there)
# Worktrees and cargo target under ../../build/. Logs: ../../spec/output/clean-*.log
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
art="$root/artifact"
b="$root/build"
mkdir -p "$b"
export CARGO_TARGET_DIR="$b/target-clean"
declare -A REF=([update]=d7176ef [baseline]=d86101c)
for rev in update baseline; do
  wt="$b/wt-$rev"
  [ -d "$wt" ] || git -C "$art" worktree add --detach "$wt" "${REF[$rev]}" >/dev/null 2>&1
  git -C "$wt" checkout -q --detach "${REF[$rev]}" && git -C "$wt" checkout -q -- . && git -C "$wt" clean -qfd tests
  echo "worktree $rev at $(git -C "$wt" rev-parse --short HEAD) ($(git -C "$wt" log -1 --format=%s))"
  f="$wt/tests/tests/client_api/t97_specula_repro.rs"
  if [ "$rev" = update ]; then
    cp "$here/t99_specula_repro.rs" "$f"; tests="specula_repro_transfer_to_learner_no_panic specula_control_trigger_elect_on_learner"
  else
    python3 - "$here/t99_specula_repro.rs" "$f" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
i=s.index('#[tracing::instrument]\n#[test_harness::test(harness = ut_harness)]\nasync fn specula_repro_transfer_to_learner_no_panic')
j=s.index('#[tracing::instrument]\n#[test_harness::test(harness = ut_harness)]\nasync fn specula_control_trigger_elect_on_learner')
open(sys.argv[2],'w').write(s[:i]+s[j:])
PY
    tests="specula_control_trigger_elect_on_learner"
  fi
  sed -i 's/^mod t16_with_raft_state;/mod t97_specula_repro;\nmod t16_with_raft_state;/' "$wt/tests/tests/client_api/main.rs"
  for t in $tests; do
    ( cd "$wt" && timeout 20m cargo +stable test -p tests --test client_api "t97_specula_repro::$t" -- --exact --nocapture --test-threads=1 ) > "$root/spec/output/clean-$rev-$t.log" 2>&1
    echo "$rev $t rc=$?"; grep -E "SPECULA_(REPRO|CONTROL)|panicked at|^Error:|test result|^error" "$root/spec/output/clean-$rev-$t.log" | head -6
  done
  git -C "$wt" checkout -q -- . && git -C "$wt" clean -qfd tests
done
