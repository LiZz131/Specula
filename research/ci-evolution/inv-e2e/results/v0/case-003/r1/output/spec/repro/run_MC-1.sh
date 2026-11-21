#!/usr/bin/env bash
# Runs the MC-1 reproduction on the updated tree (artifact commit `update`)
# and on the old tree (artifact commit `baseline`) as a control. Trees are
# exported with `git archive` into a scratch directory under .specula-output
# (the artifact working tree is not modified) and removed afterwards.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
scratch="$root/.repro-trees"
rm -rf "$scratch"; mkdir -p "$scratch"
for rev in update baseline; do
    sha="$(git -C "$root/artifact" log --all --format='%H %s' | awk -v s="$rev" '$2==s {print $1; exit}')"
    dir="$scratch/$rev"; mkdir -p "$dir"
    git -C "$root/artifact" archive "$sha" | tar -x -C "$dir"
    cp "$here/test_bugMC1_unchanged_veh_halt_test.go" "$dir/internal/consensus/specula_repro_mc1_test.go"
    log="$here/output-MC-1-$rev.log"
    {
      echo "rev: $rev (commit $sha)"
      echo "types/params.go sha256: $(sha256sum "$dir/types/params.go" | cut -d' ' -f1)"
      echo "cmd: cd <export of $rev> && timeout 10m go test -mod=readonly ./internal/consensus -run '^(TestSpeculaReproMC1UnchangedEnableHeight|TestSpeculaReproControlEnableFromZero)\$' -count=1 -v"
      (cd "$dir" && timeout 10m go test -mod=readonly ./internal/consensus \
          -run '^(TestSpeculaReproMC1UnchangedEnableHeight|TestSpeculaReproControlEnableFromZero)$' -count=1 -v 2>&1)
      echo "exit=$?"
    } > "$log" 2>&1
    echo "== $rev"; grep -E "OUTCOME|highest committed|CONSENSUS FAILURE|^(ok|FAIL|---)" "$log" | cut -c1-400
done
rm -rf "$scratch"
