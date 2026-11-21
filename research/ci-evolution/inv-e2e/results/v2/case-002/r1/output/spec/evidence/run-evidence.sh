#!/usr/bin/env bash
# Evaluate every evidence module (one fixed state or one fixed step) with TLC.
cd /work/current/.specula-output/spec/evidence
cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
lib=/work/current/.specula-output/spec:/work/current/.specula-output/spec/evidence
for id in "$@"; do
  meta=/dev/shm/specula-e2e-case-002/evidence-$id; rm -rf "$meta"
  ( cd "$id" && echo "COMMAND: cd evidence/$id && timeout 120s java -DTLA-Library=$lib -cp $cp tlc2.TLC -metadir $meta -config $id.cfg $id.tla" > tlc.log && \
    timeout 120s java -DTLA-Library=$lib -cp $cp tlc2.TLC -metadir $meta -config $id.cfg $id.tla >> tlc.log 2>&1; echo "exit $?" >> tlc.log )
  rm -rf "$meta"
  echo "== $id"; grep -E '^<<|violated|No error has been found|^Error' "$id/tlc.log" | head -4
done
