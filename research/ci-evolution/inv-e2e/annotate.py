#!/usr/bin/env python3
"""v2 input preparation: add REQ-EVIDENCE comments to each case's V0 spec.

    python3 annotate.py [--case case-002 ...] [--backend claude] [--timeout 7200] [--budget 40]

Per case, two fresh agent sessions in the bwrap sandbox, each seeing only the base
revision: its source tree, its spec, and history up to the base commit (tools/hist.sh
over WORK/history/<case>.git, which holds no later commit):

  1. annotate (prompts/annotate.md)  -> spec-annotated, checked by check_annotation.py
  2. review   (prompts/review.md)    -> spec-reviewed,  checked again

The reviewed spec is frozen at WORK/annotated/<case>/spec/ with a manifest of hashes
and costs. prepare.py overlays it on the V0 prior for v2 attempts.

--prior DIR --label L annotates another prior suite instead (e.g. a ci-init prior,
WORK/inits/{case}/r1/prior/.specular-output): sessions go to WORK/annotate-L/, the frozen result
to WORK/annotated-L/<case>/ with the prior's source path and spec hash in its manifest; use it with
prepare.py --prior DIR --annotated-root WORK/annotated-L. Comments only:
the checker rejects any change to a non-comment line or a cfg.

Requires materialize.py to have run for the case.
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import time
from datetime import datetime

from agent import limit_wait_seconds, run_agent
from check_annotation import check
from common import CASE_IDS, HERE, LIB, SPECULA, V0_ROOT, WORK, cases_json, check_case, read_json, sha256, tree_hash, write_json

GUARD = SPECULA / "research/ci-evolution/blind-incremental-bugs/tools/network-guard"
# Session and frozen-output roots; main() switches them to WORK/annotate-<label>, WORK/annotated-<label>
# for --label (annotations of a prior other than the blind V0).
SESSIONS = WORK / "annotate"
FROZEN = WORK / "annotated"
PRIOR: str | None = None  # --prior template; None = the blind V0


def prior_spec(case_id: str) -> Path:
    if PRIOR is None:
        return V0_ROOT / case_id / ".specula-output/spec"
    from prepare import resolve_prior
    return resolve_prior(PRIOR, case_id) / "spec"


def copy_spec(src: Path, dest: Path) -> None:
    for path in src.rglob("*"):
        if path.is_file() and path.suffix in (".tla", ".cfg") and "TTrace" not in path.name:
            target = dest / path.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def workspace(case_id: str, stage: str, spec_dirs: dict[str, Path], rules: str | None) -> Path:
    ws = SESSIONS / case_id / stage / "ws"
    if ws.exists():
        shutil.rmtree(ws)
    ws.mkdir(parents=True)
    for name, src in spec_dirs.items():
        copy_spec(src, ws / name)
    shutil.copytree(WORK / "subjects" / case_id / "old-tree", ws / "source", symlinks=True)
    shutil.copytree(WORK / "history" / f"{case_id}.git", ws / "history.git")
    (ws / "tools").mkdir()
    shutil.copy2(HERE / "tools/hist.sh", ws / "tools/hist.sh")
    shutil.copytree(GUARD, ws / "tools/network-guard")
    for f in [ws / "tools/hist.sh", *(ws / "tools/network-guard").iterdir()]:
        f.chmod(0o755)
    (ws / "lib").mkdir()
    for jar in ("tla2tools.jar", "CommunityModules-deps.jar"):
        shutil.copy2(LIB / jar, ws / "lib" / jar)
    if rules:
        (ws / "ANNOTATION-RULES.md").write_text(rules)
    (ws / "out/tmp").mkdir(parents=True)
    (ws / ".cache/tmp").mkdir(parents=True)
    return ws


def render(template: str, case: dict) -> str:
    return template.replace("{{SYSTEM}}", case["system"]).replace("{{MODULE}}", case["module"])


def session(case_id: str, stage: str, ws: Path, prompt: str, args) -> dict:
    ro = [p.name for p in ws.iterdir() if p.name not in ("out", ".cache")]
    return run_agent(backend=args.backend, workspace=ws, ro=ro, rw=["out", ".cache"], prompt=prompt,
                     log_dir=SESSIONS / case_id / stage / "log", timeout_s=args.timeout,
                     budget_usd=args.budget, meta={"case_id": case_id, "stage": stage})


def annotate(case_id: str, args) -> dict:
    final = FROZEN / case_id
    if (final / "manifest.json").exists():
        print(f"{case_id}: already annotated", flush=True)
        return {"case_id": case_id, "status": "exists"}
    case = cases_json()[case_id]
    v0_spec = prior_spec(case_id)
    annotate_prompt = render((HERE / "prompts/annotate.md").read_text(), case)
    stage1 = SESSIONS / case_id / "1-annotate"
    resumable = (args.resume and (stage1 / "log/run-manifest.json").exists()
                 and read_json(stage1 / "log/run-manifest.json").get("status") == "EXITED_0"
                 and not (SESSIONS / case_id / "2-review").exists())
    if resumable:
        # Reuse a completed annotate session (e.g. after a checker fix); only the check is redone.
        ws1, m1 = stage1 / "ws", read_json(stage1 / "log/run-manifest.json")
        print(f"{case_id}: resuming from the completed annotate session", flush=True)
    else:
        if (SESSIONS / case_id).exists():
            raise SystemExit(f"{case_id}: a previous attempt exists at {WORK / 'annotate' / case_id}; "
                             "move it away first, or use --resume after a completed annotate session")
        ws1 = workspace(case_id, "1-annotate", {"spec-original": v0_spec}, None)
        m1 = session(case_id, "1-annotate", ws1, annotate_prompt, args)
        if m1["status"] in ("USAGE_LIMIT", "AUTH_ERROR"):
            return {"case_id": case_id, "status": "USAGE_LIMIT", "manifest": m1, "stage": "1-annotate", "auth": m1["status"] == "AUTH_ERROR"}
    c1 = check(ws1 / "spec-original", ws1 / "out/spec-annotated")
    write_json(SESSIONS / case_id / "1-annotate/check.json", c1)
    print(f"{case_id}: annotate {m1['status']} ${m1['behavior']['cost_usd']} check ok={c1['ok']}", flush=True)
    if not c1["ok"]:
        return {"case_id": case_id, "status": "ANNOTATE_CHECK_FAILED", "problems": c1["problems"][:10]}

    ws2 = workspace(case_id, "2-review", {"spec-original": v0_spec, "spec-annotated": ws1 / "out/spec-annotated"},
                    annotate_prompt)
    m2 = session(case_id, "2-review", ws2, render((HERE / "prompts/review.md").read_text(), case), args)
    if m2["status"] in ("USAGE_LIMIT", "AUTH_ERROR"):
        return {"case_id": case_id, "status": "USAGE_LIMIT", "manifest": m2, "stage": "2-review", "auth": m2["status"] == "AUTH_ERROR"}
    c2 = check(ws2 / "spec-original", ws2 / "out/spec-reviewed")
    write_json(SESSIONS / case_id / "2-review/check.json", c2)
    print(f"{case_id}: review {m2['status']} ${m2['behavior']['cost_usd']} check ok={c2['ok']} "
          f"model-talk warnings={len(c2['warnings'])}", flush=True)
    for w in c2["warnings"]:
        print(f"  WARN {w}", flush=True)
    if not c2["ok"]:
        return {"case_id": case_id, "status": "REVIEW_CHECK_FAILED", "problems": c2["problems"][:10]}

    final.mkdir(parents=True)
    shutil.copytree(ws2 / "out/spec-reviewed", final / "spec")
    for name in ("decisions.md", "summary.md", "provenance.md", "concerns.md"):
        if (ws2 / "out" / name).exists():
            shutil.copy2(ws2 / "out" / name, final / f"review-{name}")
    for name in ("ledger.md", "provenance.md", "concerns.md"):
        if (ws1 / "out" / name).exists():
            shutil.copy2(ws1 / "out" / name, final / f"annotate-{name}")
    manifest = {
        "schema_version": 1,
        "case_id": case_id,
        **({"v0_spec_tree_sha256": tree_hash(v0_spec)} if PRIOR is None else
           {"prior_source": str(v0_spec.parent), "prior_spec_tree_sha256": tree_hash(v0_spec),
            "prior_label": FROZEN.name.removeprefix("annotated-")}),
        "annotated_spec_tree_sha256": tree_hash(final / "spec"),
        "prompts": {name: sha256(HERE / "prompts" / name) for name in ("annotate.md", "review.md")},
        "hist_sh_sha256": sha256(HERE / "tools/hist.sh"),
        "sessions": {
            "annotate": {k: m1[k] for k in ("status", "model", "effort", "wall_seconds")} | {"cost_usd": m1["behavior"]["cost_usd"], "contaminated": m1["behavior"]["network_audit"]["contaminated"]},
            "review": {k: m2[k] for k in ("status", "model", "effort", "wall_seconds")} | {"cost_usd": m2["behavior"]["cost_usd"], "contaminated": m2["behavior"]["network_audit"]["contaminated"]},
        },
        "check": {k: c2[k] for k in ("ok", "properties", "blocks", "status_counts", "warnings")},
        "frozen": True,
    }
    write_json(final / "manifest.json", manifest)
    return {"case_id": case_id, "status": "FROZEN", "status_counts": c2["status_counts"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--backend", default="claude", choices=("claude", "codex"))
    parser.add_argument("--timeout", type=int, default=7200)
    parser.add_argument("--budget", type=float, default=40.0)
    parser.add_argument("--resume", action="store_true", help="reuse a completed annotate session and continue with review")
    parser.add_argument("--max-attempts", type=int, default=10, help="usage-limit retries per case")
    parser.add_argument("--prior", help="annotate this prior instead of the blind V0 (output directory; "
                        "`{case}` is replaced by the case ID); needs --label")
    parser.add_argument("--label", help="prior label: sessions in WORK/annotate-<label>, frozen output in "
                        "WORK/annotated-<label>/<case> (prepare.py --annotated-root)")
    args = parser.parse_args()
    global SESSIONS, FROZEN, PRIOR
    if args.prior and not args.label:
        raise SystemExit("--prior needs --label, so the annotations do not mix with the V0 ones")
    if args.label:
        if not args.label.replace("-", "").replace("_", "").isalnum():
            raise SystemExit(f"bad --label {args.label!r}")
        SESSIONS, FROZEN = WORK / f"annotate-{args.label}", WORK / f"annotated-{args.label}"
    PRIOR = args.prior
    results = []
    for case_id in args.cases or CASE_IDS:
        check_case(case_id)
        for attempt in range(1, args.max_attempts + 1):
            result = annotate(case_id, args)
            if result["status"] != "USAGE_LIMIT":
                break
            # Usage limit: archive the whole case attempt, wait for the reset, start over.
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            dest = WORK / "invalid" / f"{SESSIONS.name}-{case_id}-a{attempt}-{stamp}"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(SESSIONS / case_id), str(dest))
            stderr = dest / result["stage"] / "log/stderr.log"
            wait = 60 if result.get("auth") else limit_wait_seconds(result["manifest"]["behavior"], stderr)
            print(f"{case_id}: USAGE_LIMIT in {result['stage']} (attempt {attempt}); archived to {dest}; wait {wait}s", flush=True)
            result = {"case_id": case_id, "status": "USAGE_LIMIT", "archived": str(dest)}
            if wait is None:
                print("usage limit without a 5-hour reset time; stopping", flush=True)
                results.append(result)
                write_json(SESSIONS / "summary.json", results)
                return 2
            time.sleep(wait)
        results.append(result)
    write_json(SESSIONS / "summary.json", results)
    for r in results:
        print(r, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
