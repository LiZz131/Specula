#!/usr/bin/env bash
# SANY parse of each module; log to spec/output/sany-<module>.log
set -u
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc_all=0
for m in "$@"; do
  log="$spec_dir/output/sany-${m%.tla}.log"
  (cd "$spec_dir" && timeout 5m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tla2sany.SANY "$m") > "$log" 2>&1
  rc=$?; echo "# exit: $rc" >> "$log"
  if grep -q "Semantic errors\|Parsing or semantic analysis failed\|\*\*\* Errors" "$log" || [ $rc -ne 0 ]; then echo "$m: FAIL"; rc_all=1; tail -20 "$log"; else echo "$m: OK"; fi
done
exit $rc_all
