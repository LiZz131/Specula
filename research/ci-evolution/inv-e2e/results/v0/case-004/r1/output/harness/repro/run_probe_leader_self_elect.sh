#!/usr/bin/env bash
# Probe leader self-election on a given revision. Usage: run_probe_leader_self_elect.sh <update|baseline>
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; suite="$(cd "$here/../.." && pwd)"
rev="$1"; tree="$suite/build/probe-$rev-source"; log="$suite/spec/output/probe-leader-self-elect-$rev.log"
rm -rf "$tree"; cp -a "$suite/artifact" "$tree"
[ "$rev" = baseline ] && git -C "$tree" checkout -q HEAD~1
echo "source: $(git -C "$tree" rev-parse HEAD) $(git -C "$tree" log -1 --format=%s)" > "$log"
cp "$here/probe_leader_self_elect.rs" "$tree/tests/tests/client_api/t92_probe_trigger.rs"
sel="t92_probe_trigger"
mods="mod t92_probe_trigger;"
if [ "$rev" = update ]; then
  cp "$here/probe_leader_transfer_self.rs" "$tree/tests/tests/client_api/t93_probe_xfer.rs"; mods="$mods\nmod t93_probe_xfer;"; sel="t9"
fi
sed -i "s/^mod t13_trigger_snapshot;\$/mod t13_trigger_snapshot;\n$mods/" "$tree/tests/tests/client_api/main.rs"
cd "$tree"
timeout 20m env CARGO_TARGET_DIR="$suite/build/cargo-target-probe-$rev" cargo +stable test -p tests --test client_api "$sel" -- --nocapture --test-threads=1 >> "$log" 2>&1
echo "EXIT rc=$?" >> "$log"
grep -E "^source|PROBE|panicked at|assertion|test result|EXIT" "$log" | cut -c1-220
