# Inputs of case-012

- `case.json`, `task.md`, `model-scope.md`, `final-schema.json`: the neutral task every arm received (a file suffixed `.<arm>` differs for that arm).
- `input-manifest.<arm>.json`: the sandbox input map of that arm's r1 workspace.
- Prior suite of v0/v1: `../../../blind-incremental-bugs/blind-incremental-v0/case-012/.specula-output/` (tree hash in `v0-suite.sha256`; `previous.<arm>.sha256` is the hash of what each arm actually got).
- `annotated/`: v2's prior suite (`spec/`, comments only) with the annotation and review reports, frozen before any v2 run.
