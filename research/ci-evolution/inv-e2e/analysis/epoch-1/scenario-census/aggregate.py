#!/usr/bin/env python3
"""Merge items/<arm>-<case>.csv into census.csv and dismissals.csv, and print per-run and per-arm totals.

    python3 aggregate.py            # writes census.csv, dismissals.csv, totals.md
"""
import csv
import collections
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLASSES = ["covered", "Q-a", "covered-not-with-check", "unclear"]
ARMS = ["v0", "v1", "v2"]
CASES = ["case-002", "case-003", "case-004", "case-006", "case-010", "case-011", "case-012"]


def read(path):
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def main():
    items, dism = [], []
    for arm in ARMS:
        for case in CASES:
            p = HERE / "items" / f"{arm}-{case}.csv"
            d = HERE / "items" / f"{arm}-{case}.dismissals.csv"
            items += read(p) if p.exists() else []
            dism += read(d) if d.exists() else []
    bad = [r for r in items if r["class"] not in CLASSES]
    if bad:
        raise SystemExit(f"unknown class in {[(r['arm'], r['case'], r['item_id'], r['class']) for r in bad]}")
    fields = list(items[0].keys())
    with (HERE / "census.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fields)
        w.writeheader()
        w.writerows(items)
    with (HERE / "dismissals.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, list(dism[0].keys()) if dism else ["arm", "case", "quote", "source", "topic"])
        w.writeheader()
        w.writerows(dism)
    run = collections.Counter((r["arm"], r["case"], r["class"]) for r in items)
    nd = collections.Counter((r["arm"], r["case"]) for r in dism)
    lines = ["| Arm | Case | Items | covered | Q-a | covered-not-with-check | unclear | Dismissals |",
             "|---|---|---:|---:|---:|---:|---:|---:|"]
    for arm in ARMS:
        for case in CASES:
            n = [run[(arm, case, c)] for c in CLASSES]
            lines.append(f"| {arm} | {case} | {sum(n)} | " + " | ".join(map(str, n)) + f" | {nd[(arm, case)]} |")
    lines += ["", "| Arm | Items | covered | Q-a | covered-not-with-check | unclear | Dismissals |",
              "|---|---:|---:|---:|---:|---:|---:|"]
    for arm in ARMS:
        n = [sum(run[(arm, case, c)] for case in CASES) for c in CLASSES]
        lines.append(f"| {arm} | {sum(n)} | " + " | ".join(map(str, n)) +
                     f" | {sum(nd[(arm, c)] for c in CASES)} |")
    n = [sum(v for k, v in run.items() if k[2] == c) for c in CLASSES]
    lines.append(f"| all | {sum(n)} | " + " | ".join(map(str, n)) + f" | {sum(nd.values())} |")
    (HERE / "totals.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
