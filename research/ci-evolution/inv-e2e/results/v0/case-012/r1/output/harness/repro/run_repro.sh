#!/usr/bin/env bash
# Reproduce finding MC-1 on the updated revision and run the identical schedule
# on the baseline revision as a control. Both trees are fresh `git archive`
# exports of the neutral synthetic commits in artifact/ (no other source).
set -uo pipefail
out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
toolchain="${SPECULA_CARGO_TOOLCHAIN:-stable}"
log_dir="$out_dir/spec/output"
run_tree() {  # <dir> <commit> <target-dir> <log>
    local dir="$1" commit="$2" tdir="$3" log="$4"
    rm -rf "$dir" && mkdir -p "$dir"
    git -C "$out_dir/artifact" archive "$commit" | tar -x -C "$dir"
    cp "$out_dir/harness/repro/t90_specula_joint_commit_repro.rs" "$dir/openraft/tests/membership/"
    cp "$out_dir/harness/repro/t91_specula_joint_commit_divergence.rs" "$dir/openraft/tests/membership/"
    printf 'mod t90_specula_joint_commit_repro;\nmod t91_specula_joint_commit_divergence;\n' >> "$dir/openraft/tests/membership/main.rs"
    ( cd "$dir" && timeout 1500s env CARGO_TARGET_DIR="$tdir" cargo +"$toolchain" test -p openraft \
        --test membership specula_ -- --nocapture --test-threads=1 ) > "$log" 2>&1
    echo "$commit rc=$?"; grep -E 'SPECULA_REPRO|SPECULA_DIVERGENCE|^test t9' "$log" | sed -E 's/leader3.membership=.*node1/... node1/' 
}
run_tree "$out_dir/repro-new-source" aa05a38 /work/.cache/cargo-target-repro-new "$log_dir/repro-new-runtime-both.log"
run_tree "$out_dir/old-control-source" ce863f4 /work/.cache/cargo-target-oldctl "$log_dir/repro-old-control-runtime-both.log"
