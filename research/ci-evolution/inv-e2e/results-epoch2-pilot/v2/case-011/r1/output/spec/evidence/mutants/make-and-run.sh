#!/usr/bin/env bash
# Regression mutants: each copies the reference suite, applies ONE behavioral
# regression (python replace on base.tla), and checks that the named update
# property detects it (expected VIOLATED). Unmutated control = Update_focused runs.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; spec="$(cd "$here/../.." && pwd)"
cp="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
: > "$here/summary.txt.new"
only="${1:-}"
run() { id=$1; prop=$2; kind=$3
  if [ -n "$only" ] && [ "$only" != "$id" ]; then return; fi
  d="$here/$id"; rm -rf "$d"; mkdir -p "$d"
  cp "$spec"/{base.tla,MC.tla,Update.tla,UpdateProps.tla} "$d/"
  python3 "$here/mutate.py" "$id" "$d/base.tla" || { echo "$id MUTATION-NOT-APPLIED" | tee -a "$here/summary.txt.new"; return; }
  sed '/^INVARIANTS/,$d' "$spec/Update_focused.cfg" | sed 's/MaxElectionCount = 3/MaxElectionCount = 2/' > "$d/check.cfg"
  printf '%s %s\n' "$kind" "$prop" >> "$d/check.cfg"
  (cd "$d" && timeout 15m java -Xmx8g -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=600 -cp "$cp" tlc2.TLC -workers 4 \
     -metadir /dev/shm/specular-e2e-case-011/mut-$id -config check.cfg Update > tlc.log 2>&1)
  rm -rf /dev/shm/specular-e2e-case-011/mut-$id
  if grep -qE "(Invariant|Action property|Temporal properties).*violated|$prop is violated" "$d/tlc.log"; then got=VIOLATED; elif grep -q "No error" "$d/tlc.log"; then got=NOT-DETECTED; else got=OTHER; fi
  echo "$id prop=$prop got=$got" | tee -a "$here/summary.txt.new"
}
run M-U1-prevote-req-adopts-vote PreVoteResponderSideEffectFree PROPERTY
run M-U2-pre-elect-bumps-term PreVoteRequesterSideEffectFree PROPERTY
run M-U3-elect-skips-term PreVoteElectionAtPreVotedTerm PROPERTY
run M-U7-follow-keeps-precandidate PreCandidateTracksNextTerm INVARIANT
# merge: keep prior lines for mutants not rerun
if [ -n "$only" ] && [ -f "$here/summary.txt" ]; then grep -v "^$only " "$here/summary.txt" >> "$here/summary.txt.new"; fi
sort -o "$here/summary.txt" "$here/summary.txt.new"; rm -f "$here/summary.txt.new"
