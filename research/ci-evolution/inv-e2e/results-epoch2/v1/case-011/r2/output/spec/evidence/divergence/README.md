# Divergence evidence (spec/invariant-evidence.json)

`OldBase.tla` is `/work/previous/.specular-output/spec/base.tla` with only the MODULE line renamed. The other
`.tla` files are copies of the final `spec/` modules. `EvidenceTrace.tla` extends `Trace` and, on every state
of a replayed fresh trace, prints the prior and current verdicts of each affected property (plus the
documented short edits/controls). Command per trace:

    SPECULAR_TRACE=/work/current/.specular-output/traces/<name>.ndjson \
      java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 -deadlock \
      -config EvidenceTrace.cfg EvidenceTrace

Logs: `ev-<name>.log` (lines starting `<<"EVIDENCE"`).
