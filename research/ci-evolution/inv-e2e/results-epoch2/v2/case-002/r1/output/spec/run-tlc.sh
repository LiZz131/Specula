#!/usr/bin/env bash
# Usage: run-tlc.sh <id> <module.tla> <cfg> <minutes> [extra TLC args...]
# Bounded TLC run: state dir under /dev/shm/specula-e2e-case-002/, log in
# spec/output/mc/<id>.log, ledger line appended, state dir removed afterwards.
set -uo pipefail
spec_root=/work/current/.specula-output/spec
id="$1"; module="$2"; cfg="$3"; minutes="$4"; shift 4
cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
log_dir="$spec_root/output/mc"; mkdir -p "$log_dir"
meta=/dev/shm/specula-e2e-case-002/mc-$id-$$
mkdir -p "$meta"
log="$log_dir/$id.log"
workers=${WORKERS:-16}; heap=${HEAP:-24g}
outer=$(( minutes * 60 + 300 ))
cmd=(timeout "${outer}s" java -Xmx$heap -XX:+UseParallelGC -cp "$cp" tlc2.TLC -config "$cfg" -metadir "$meta" -workers "$workers" -cleanup -noGenerateSpecTE "$@" "$module")
[[ "$minutes" -gt 0 ]] && cmd=(timeout "${outer}s" java -Xmx$heap -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$(( minutes * 60 )) -cp "$cp" tlc2.TLC -config "$cfg" -metadir "$meta" -workers "$workers" -cleanup -noGenerateSpecTE "$@" "$module")
start=$(date -u +%FT%TZ)
{ echo "COMMAND: cd $spec_root && ${cmd[*]}"; echo "STARTED: $start"; } > "$log"
(cd "$spec_root" && "${cmd[@]}") >> "$log" 2>&1
ec=$?
rm -rf "$meta"
fin=$(date -u +%FT%TZ)
echo "FINISHED: $fin exit=$ec" >> "$log"
viol=$(grep -m1 -oE "(Invariant|Action property|Temporal properties?) [A-Za-z0-9_]* ?(is|were) violated" "$log" | head -1)
done_=$(grep -c "Model checking completed. No error has been found." "$log")
stats=$(grep -E "states generated, [0-9]+ distinct states found" "$log" | tail -1)
depth=$(grep -oE "depth of the complete state graph search is [0-9]+" "$log" | tail -1)
printf '{"id":"%s","module":"%s","cfg":"%s","minutes":%s,"exit":%s,"completed_no_error":%s,"violation":"%s","stats":"%s","depth":"%s","started":"%s","finished":"%s","log":"spec/output/mc/%s.log"}\n' \
  "$id" "$module" "$cfg" "$minutes" "$ec" "$done_" "$viol" "$stats" "$depth" "$start" "$fin" "$id" >> "$log_dir/ledger.ndjson"
echo "$id exit=$ec done=$done_ viol=[$viol] $stats $depth"
