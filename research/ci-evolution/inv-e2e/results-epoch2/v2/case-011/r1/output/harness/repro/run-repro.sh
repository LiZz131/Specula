#!/usr/bin/env bash
# Runs the U2 real-runtime observation on a source tree (default: updated work copy).
# Usage: run-repro.sh [source-dir] [log-file]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:-$here/../work/source-new}"; log="${2:-$here/../../spec/output/repro-MC-1-new.log}"
cp "$here/t13_specula_stale_prevote_repro.rs" "$src/tests/tests/elect/"
grep -q 'mod t13_specula_stale_prevote_repro;' "$src/tests/tests/elect/main.rs" || \
    echo 'mod t13_specula_stale_prevote_repro;' >> "$src/tests/tests/elect/main.rs"
cd "$src"
{ echo "COMMAND: cd $src && RUSTUP_TOOLCHAIN=stable timeout 20m cargo test -p tests --test elect specula_repro -- --nocapture --test-threads=1";
  echo "SOURCE: $src"; } > "$log"
RUST_BACKTRACE=1 RUSTUP_TOOLCHAIN=stable CARGO_TARGET_DIR="${SPECULA_CARGO_TARGET_DIR:-/work/.cache/cargo-target/new}" \
  timeout 20m cargo test -p tests --test elect specula_repro -- --nocapture --test-threads=1 >> "$log" 2>&1
rc=$?; echo "EXIT=$rc" >> "$log"
grep -E "SPECULA-OBSERVE|test result|panicked|assertion" "$log" | head -10
exit 0
