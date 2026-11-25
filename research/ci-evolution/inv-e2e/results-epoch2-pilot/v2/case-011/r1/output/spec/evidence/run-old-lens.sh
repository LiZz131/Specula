#!/usr/bin/env bash
# Evaluate prior/current/alternative property definitions on validated traces.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$spec_dir"
cp="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
out=evidence/old-lens; mkdir -p "$out"; : > "$out/summary.txt"
run() { # id trace invariant expected(PASS|VIOLATED)
  id=$1; t=$2; inv=$3; exp=$4
  cfg="$out/$id.cfg"
  sed '/^INVARIANTS/,$d' Trace.cfg > "$cfg"; printf 'INVARIANTS\n    TraceTypeOK\n    %s\n\nPROPERTIES\n    TraceConsumed\n' "$inv" >> "$cfg"
  log="$out/$id.log"
  timeout 5m env SPECULAR_TRACE="../traces/$t.ndjson" java -cp "$cp" tlc2.TLC -workers 1 \
     -metadir /dev/shm/specular-e2e-case-011/ev-$id -config "$cfg" EvidenceOld > "$log" 2>&1
  rm -rf /dev/shm/specular-e2e-case-011/ev-$id
  if grep -q "No error has been found" "$log"; then got=PASS; elif grep -q "Invariant $inv is violated" "$log"; then got=VIOLATED; else got=OTHER; fi
  cur=$(grep -o 'cursor = [0-9]*' "$log" | tail -1)
  echo "$id trace=$t inv=$inv expected=$exp got=$got ${cur}" | tee -a "$out/summary.txt"
}
run E-TypeOK-old      prevote_elect_multi         OldTypeOK                         VIOLATED
run E-TypeOK-ctl      prevote_elect_multi         ControlUnknownKindRejected        PASS
run E-Granted-keep    prevote_req_grant           OldGrantedResponseAfterDurable    PASS
run E-Granted-alt     prevote_req_grant           AltGrantedResponseAllKinds        VIOLATED
run E-VoteReq-keep    prevote_elect_multi         OldVoteRequestAfterDurable        PASS
run E-VoteReq-alt     prevote_elect_multi         AltVoteRequestAllKinds            VIOLATED
run E-NoForged-keep   prevote_elect_multi         OldNoForgedMessageEndpoints       PASS
run E-Leader-keep     candidate_prevote_establish OldLeaderRoleHasCommittedSelfVote PASS
run E-Candidate-keep  candidate_prevote_establish OldCandidateRoleHasPendingSelfVote PASS
run E-Certified-keep  candidate_prevote_establish OldCertifiedLeaderHasFrozenQuorum PASS
run E-Durable-keep    prevote_quorum_elect        OldDurableVoteNotAhead            PASS
