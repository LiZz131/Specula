# Blind incremental cases: commits and V0 models

`cases.json` lists, for each of the 12 cases, the upstream repository, the modeled module, the base commit (the immediate pre-update revision) and the update commit (the revision that introduced the bug).

`case-XXX/.specula-output/` is the V0 Specula suite generated from the base commit only, exactly as given to the incremental runs. `case-XXX/scope.md` is the module boundary that V0 was asked to model. Every included V0 passed the baseline audit.

case-008 and case-009 have no V0: none of their baseline attempts passed the audit.

Fixed revisions, bug descriptions and grading oracles are not included, so the cases can still be used blind.
