#!/usr/bin/env bash
# Static evaluation of property-decision evidence states (spec/evidence/<ID>/).
set -uo pipefail
spec="$(cd "$(dirname "${BASH_SOURCE[0]}")/../spec" && pwd)"
state="/dev/shm/specula-e2e-case-011/evidence-$$"; trap 'rm -rf "$state"' EXIT; mkdir -p "$state"
for d in "$spec"/evidence/E*/; do
  id="$(basename "$d")"
  ( cd "$d" && timeout 3m java -DTLA-Library="$spec:$spec/evidence" -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
      tlc2.TLC -deadlock -workers 1 -metadir "$state/$id" -config "$id.cfg" "$id.tla" > tlc.log 2>&1 )
  rm -rf "$state/$id"
  echo "$id: $(grep -E '^<<"E' "$d/tlc.log" | tr '\n' ' ') $(grep -E '^Error' "$d/tlc.log" | head -1)"
done
