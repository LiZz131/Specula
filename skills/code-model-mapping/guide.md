# Code-to-Model Mapping

`spec/code-map.json` records how the implementation corresponds to the TLA+ suite. It is a persistent CI asset, maintained like `instrumentation-spec.md` and published with the model. It is not a per-update change contract.

The map serves one purpose: when the source changes, it tells you which model elements the change touches, which unchanged elements read the affected state, and which changed code corresponds to nothing in the model. It orders review. It never proves that a change is irrelevant.

## Who Owns What

`specula code-map` owns the extracted part. Do not edit it by hand; fix its inputs and rerun `extract`.

- every constant, variable, helper, variable group, `Init`, Action, and enabled property of `base.tla` (and properties defined in `MC.tla`), with its kind;
- code anchors already written in `base.tla` comments, `instrumentation-spec.md`, and `instrumentation-map.json`, each resolved against the source tree;
- read and write footprints, Trace event names, cfg files enabling each property, and getter projections from the instrumentation tables;
- constant categories inferred from cfg values: `enum` (a model value), `world` (a set), or `bound` (a number);
- `issues`: anchors that do not resolve, and code citations in comments that belong to no element.

You own the `agent` object of each element and the top-level `code_state` and `out_of_scope` lists. `extract` preserves them for elements that still exist.

```json
"Recover": {
  "kind": "action",
  "code": [],
  "agent": {
    "status": "environment",
    "note": "Restart path: raft_new followed by load of persisted term/vote; volatile state reset.",
    "code": [{"path": "src/raft_server.c", "lines": [69, 94], "role": "restart", "functions": ["raft_new"]}]
  }
}
```

`agent.status` is one of:

| Status | Use for |
|---|---|
| `mapped` | The element corresponds to the cited code. Add `agent.code` when the extracted anchors are missing or incomplete. |
| `environment` | Faults, network behavior, schedulers, or external callers. Cite the assumption and the code it depends on (persistence callbacks, transport API, public entry point). |
| `model-glue` | Helpers with no implementation counterpart, such as message-bag operations. |
| `check-parameter` | World sizes and exploration bounds not inferred automatically. |
| `requirement` | Properties. Cite the source of the requirement: paper, design document, code assertion, test, or issue. |
| `abstraction` | Intentional summaries of implementation state or steps. Say what is summarized. |
| `out-of-scope` | Elements kept for structure but outside the modeled behavior. Say why. |

Every status other than `mapped` requires a `note`. Every `agent.code` entry uses a repository-relative `path` and a `lines` range; add `functions` and `role` (`entry`, `guard`, `effect`, `callee`, `persistence`, `restart`, `declaration`, `projection`) when known.

`code_state` lists implementation state that the model does not represent but that changes the behavior of mapped elements, for example a flag in an Action's guard that the model abstracts away:

```json
{"code": "raft_server_private_t.snapshot_in_progress", "affects": ["Timeout"], "note": "raft_periodic skips elections while a snapshot is in progress (raft_server.c:242); abstracted away."}
```

Write `code` as code names only: `struct.field`, or several field and flag names separated by `/` when one effect depends on all of them. Put explanations in `note`. `impact` matches names containing an underscore as whole words and other field names only as member access (`->field`, `.field`); it ignores type names ending in `_t` and plain words.

`out_of_scope` lists code that is deliberately outside the model, with the reason taken from the modeling brief:

```json
{"path": "src/raft_server.c", "symbol": "raft_add_node", "reason": "Membership changes excluded by the modeling brief."}
```

`path` accepts shell-style globs. Omit `symbol` to cover a whole file or directory.

## Building or Completing a Map

Do this when a CI baseline or BYOM model is final, or when an incremental run finds no map in the prior artifacts.

1. Run `specula code-map extract --work=<output directory> --source=<source tree the model describes>`.
2. Fix every `invalid-anchor` issue at its origin: correct the citation in `base.tla` or `instrumentation-spec.md` after reading the cited code, then rerun `extract`. Do not delete a citation to silence the issue.
3. Resolve every `unattached-anchor` issue: move the comment next to the element it describes, or record the information in `code_state` or an element's `agent.note`.
4. Run `specula code-map check --work=<output directory>` and close each error:
   - **Enum constants**: cite the implementation type or definition (state enum, message type, entry kind). If a model value has no implementation counterpart, classify it.
   - **Variables**: cite the field or structure, and record the projection used by the trace harness when it is not already extracted. Note whether the state is persistent, volatile, derived, or environment state. A model variable may summarize several implementation fields; say so.
   - **Actions**: cite the entry function and, where they matter, the guard, effect, and persistence code. One Action may span several functions, and one function may serve several Actions; record each relation. Fault and network Actions are `environment`; anchor them to the persistence and transport code whose behavior they assume.
   - **Properties**: cite the requirement source with `requirement`. A property is not mapped to code merely because code enforces it. Type, structural, and bookkeeping invariants that exist only to keep the model well formed are `model-glue`; do not label them `requirement` without an external source.
   - **Partial correspondence**: when an element represents only part of the implementation behavior it names (for example, a variable whose ordinary updates are not modeled), use `abstraction` and say which part is omitted, rather than `mapped`.
   - **Helpers**: warnings only. Classify getter mirrors as `mapped` and pure modeling helpers as `model-glue`.
5. Read the guards of each mapped entry function for implementation state that the model omits. Record each such state in `code_state`.
6. Record the code areas excluded by the modeling brief in `out_of_scope`.
7. Rerun `check` until it reports `code map complete`.

Cite only code you have read. A precise partial map is more useful than a complete guess.

## Projecting a Source Update (update-scope.json)

Use this in incremental Chapter 1, before choosing the disposition. The result is `spec/update-scope.json`: one recorded decision for every changed hunk and every model element the update may touch. The tool checks that nothing was skipped and derives the disposition from your decisions.

1. Make sure the working artifacts have a map for the **old** source. If the prior artifacts have none, build it first against the old source tree, before editing any spec.
2. Run `specula code-map impact --work=<working output directory> --diff=<source diff> --old-source=<old source> --new-source=<new source> --json=<impact.json>`. For changed functions with no anchor, `impact` walks their callers with the language's call-graph tool until it reaches a mapped function. Add `--callgraph=none` only if the tool cannot run.
3. Run `specula code-map scope init --work=<working output directory> --impact=<impact.json>`. It writes the skeleton with every hunk (`H1`, `H2`, ...), every directly reached, caller-reached, or hidden-state element, the new functions, and the interaction and property candidates.
4. Fill in every hunk's `disposition`, `evidence`, and, for `reaches-model`, `via` (the model elements it reaches):

   | Disposition | Use when | What the check requires |
   |---|---|---|
   | `reaches-model` | the change alters behavior that the listed elements model, directly or through callers, shared state, persistence, or assumptions | `via` names elements that also appear in `elements` with a verdict |
   | `no-behavior-change` | logging, renaming, refactoring, or comments with no effect on modeled behavior | evidence that explains why, especially when `impact` linked the hunk to elements |
   | `out-of-scope` | the code is outside the modeling scope | a matching `out_of_scope` entry in `code-map.json` (add it, with the brief's reason) |
   | `map-gap` | modeled code the map does not cite | a valid anchor covering it in `code-map.json` (add it, then `extract`) |
   | `non-model-file` | tests, build, documentation, or configuration that do not change implementation behavior | evidence |

   Read the hunk and the caller path before deciding. A caller path proves only that the code can run under a mapped function, not that the change alters modeled behavior; a hunk without a path is not thereby irrelevant.
5. Give every element a `verdict` and `evidence`: `changed` (its modeled behavior must change), `unchanged` (reviewed; same behavior), or `now-wrong` (the existing model was already wrong here; record it as a repair). Add elements that your `via` lists name and the skeleton does not include.
6. Give every new function a verdict: `new-action`, `new-environment-step`, or `internal`.
7. Put every interaction candidate in `interaction.selected` or `interaction.rejected`, and every property candidate in `properties.recheck` or `properties.skip`, each with a reason. Selected interactions become `InteractionActions`.
8. Run `specula code-map scope check --work=<working output directory>` until it reports `update scope complete`. It writes `derived`: the disposition (`MODEL_CHANGE_REQUIRED` when any element is `changed` or `now-wrong` or a new step is needed), the affected Actions, selected interactions, properties to recheck, and repairs. Use `derived` as the Chapter 1 result; do not state a different disposition.
9. Read the complete diff anyway. The report and the scope order the review; they do not judge semantics for you.

## Refreshing the Map After an Update

After the reference suite is final (incremental Chapter 5), rerun `extract` against the **new** source, update the `agent` entries of elements whose code or meaning changed, add entries for new elements, and rerun `check`. Keep source-driven map changes and corrections of previously wrong map entries apart in the changelog, as with model repairs.

## Rules

- The map supplements reading the code; it never replaces it.
- An unmapped change is a question to answer, not evidence of irrelevance.
- Do not weaken the model, a property, or a citation to make `check` pass.
- Keep citations specific: file, line range, and function. Line numbers drift; `extract` re-resolves them against the source, so refresh the map whenever the source changes.
