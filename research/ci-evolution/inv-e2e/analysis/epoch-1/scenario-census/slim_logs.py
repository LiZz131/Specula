#!/usr/bin/env python3
"""Shrink runs/*/*/logs/*.log to the lines that carry results.

Keeps: the TLC version and 'Running Random Simulation' lines, probe hits (`update-coverage`), Error lines and
the three lines after each, the last Progress line, and the final summary lines. Drops SANY parse/semantic/lint
chatter. result.json is untouched (it holds what each pass reached, its status and trace count).
"""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEEP = re.compile(r"^(TLC2 Version|Running Random Simulation|<<\s*\"update-coverage|Error|Finished in|"
                  r"The number of states|Starting\.\.\.|\[\.\.\. trimmed)")

for log in sorted(HERE.glob("runs/*/*/logs/*.log")):
    lines = log.read_text(errors="replace").splitlines()
    keep = set()
    for i, line in enumerate(lines):
        if KEEP.match(line) or "update-coverage" in line:
            keep.add(i)
        if line.startswith("Error"):
            keep |= {i + 1, i + 2, i + 3}
    progress = [i for i, line in enumerate(lines) if line.startswith("Progress")]
    if progress:
        keep.add(progress[-1])
    out = [lines[i] for i in sorted(keep) if i < len(lines) and not lines[i].startswith("[... trimmed")]
    log.write_text("\n".join(out) + "\n")
