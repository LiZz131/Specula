#!/usr/bin/env bash
# Run the Specular reproduction tests on a source tree (default: current
# instrumented copy). A FAILED test means the defect was triggered (the tests
# assert the correct behavior). Usage: run-repro.sh [source-tree] [log-name]
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="${1:-$suite_root/work-source}"
log="$suite_root/harness/repro/${2:-repro-current}.log"
cp "$suite_root/harness/repro/t13_specular_pre_vote_repro.rs" "$src/tests/tests/elect/"
grep -q "mod t13_specular_pre_vote_repro;" "$src/tests/tests/elect/main.rs" || \
    echo "mod t13_specular_pre_vote_repro;" >> "$src/tests/tests/elect/main.rs"
{ echo "# source: $src HEAD $(git -C "$src" rev-parse HEAD 2>/dev/null)"; echo "# started $(date -u +%FT%TZ)"; } > "$log"
cd "$src"
timeout 30m cargo test -p tests --test elect t13_specular_pre_vote_repro -- --nocapture --test-threads=1 >> "$log" 2>&1
echo "# exit: $? finished $(date -u +%FT%TZ)" >> "$log"
grep -E "SPECULAR-REPRO|test .* \.\.\. |test result" "$log"
