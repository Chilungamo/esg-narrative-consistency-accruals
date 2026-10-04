#!/usr/bin/env python3
"""Summarise a SAS log from run_all.sas: errors, warnings and suspicious notes,
attributed to the program (00-05) that produced them, plus row counts.

    python3 check_log.py run_all.log            # human-readable report
    python3 check_log.py run_all.log --strict   # also exit 1 on warnings

Exit code: 0 clean, 1 warnings/suspicious notes (with --strict), 2 errors.
Standard library only, so it runs on WRDS Cloud's python3.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import OrderedDict

# NOTE lines that are not errors but usually mean a silent data problem.
SUSPICIOUS_NOTES = [
    (r"uninitialized", "uninitialized variable"),
    (r"MERGE statement has more than one data set with repeats of BY values",
     "many-to-many MERGE"),
    (r"Missing values were generated as a result", "missing values generated"),
    (r"Invalid (data|argument|numeric data)", "invalid data/argument"),
    (r"converted to (numeric|character) values", "implicit type conversion"),
    (r"At least one W\.D format was too small", "format too narrow"),
    (r"Division by zero", "division by zero"),
    (r"Mathematical operations could not be performed", "math error"),
    (r"The query requires remerging summary statistics", "SQL remerge"),
    (r"The execution of this query involves performing one or more Cartesian",
     "SQL Cartesian product"),
    (r"SAS went to a new line when INPUT statement reached past",
     "INPUT past end of line"),
    (r"The SAS System stopped processing this step because of errors",
     "step stopped by errors"),
    (r"SAS set option OBS=0 and will continue to check statements",
     "syntax-check mode (later steps did not run)"),
]
# WARNINGs that are routine on WRDS and not worth flagging.
BENIGN_WARNINGS = [
    r"Unable to copy SASUSER registry",
    r"The quoted string currently being processed has become more than 262",
]

RE_START = re.compile(r"\[run_all\] >>> (\S+) start")
RE_END = re.compile(r"\[run_all\] <<< (\S+) end syscc=(\d+) elapsed=(\S+)")
RE_OBS = re.compile(
    r"NOTE: (?:The data set|Table) (\S+) (?:has|created, with) (\d+) "
    r"(?:observations|rows) and (\d+) (?:variables|columns)")
RE_ASSERT = re.compile(r"\[assert_unique\]")
RE_LINE_NO = re.compile(r"^\s*\d+\s")  # echoed source lines start with a number


def check(path: str, max_per_type: int = 15) -> tuple[str, int, int]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()

    prog = "(before run_all markers)"
    progs: "OrderedDict[str, dict]" = OrderedDict()

    def bucket(p: str) -> dict:
        return progs.setdefault(p, {"errors": [], "warnings": [], "notes": [],
                                    "datasets": OrderedDict(), "asserts": [],
                                    "end": None})

    i = 0
    while i < len(lines):
        line = lines[i]
        m = RE_START.search(line)
        if m and line.startswith("NOTE"):
            prog = m.group(1)
            bucket(prog)
            i += 1
            continue
        m = RE_END.search(line)
        if m and line.startswith("NOTE"):
            bucket(m.group(1))["end"] = (int(m.group(2)), m.group(3))
            i += 1
            continue

        b = bucket(prog)
        # SAS wraps long messages: continuation lines are indented.
        msg = line
        j = i + 1
        while (j < len(lines) and lines[j].startswith("      ")
               and not RE_LINE_NO.match(lines[j])):
            msg += " " + lines[j].strip()
            j += 1
        loc = f"line {i + 1}"

        if msg.startswith("ERROR"):
            b["errors"].append(f"{loc}: {msg}")
        elif msg.startswith("WARNING"):
            if not any(re.search(p, msg) for p in BENIGN_WARNINGS):
                b["warnings"].append(f"{loc}: {msg}")
        elif msg.startswith("NOTE"):
            if RE_ASSERT.search(msg):
                b["asserts"].append(msg[len("NOTE: "):])
            for pat, label in SUSPICIOUS_NOTES:
                if re.search(pat, msg):
                    b["notes"].append(f"{loc}: [{label}] {msg}")
                    break
            m = RE_OBS.search(msg)
            if m:
                b["datasets"][m.group(1).upper()] = (int(m.group(2)), int(m.group(3)))
        i = j

    n_err = sum(len(b["errors"]) for b in progs.values())
    n_warn = sum(len(b["warnings"]) + len(b["notes"]) for b in progs.values())

    out = [f"SAS log check: {path}",
           f"  {n_err} error(s), {n_warn} warning(s)/suspicious note(s)", ""]
    for p, b in progs.items():
        if p.startswith("(") and not (b["errors"] or b["warnings"] or b["notes"]):
            continue
        end = b["end"]
        status = ("NOT FINISHED" if end is None
                  else f"syscc={end[0]} elapsed={end[1]}")
        out.append(f"=== {p}  [{status}]")
        for key, title in (("errors", "ERRORS"), ("warnings", "WARNINGS"),
                           ("notes", "SUSPICIOUS NOTES")):
            items = b[key]
            if items:
                out.append(f"  {title} ({len(items)}):")
                out += [f"    {x}" for x in items[:max_per_type]]
                if len(items) > max_per_type:
                    out.append(f"    ... {len(items) - max_per_type} more")
        if b["asserts"]:
            out.append("  KEY CHECKS:")
            out += [f"    {x}" for x in b["asserts"]]
        perm = [(k, v) for k, v in b["datasets"].items() if not k.startswith("WORK._")]
        if perm:
            out.append("  DATASETS (last write):")
            out += [f"    {k:<40} {v[0]:>10,} obs  {v[1]:>4} vars" for k, v in perm]
            empty = [k for k, v in perm if v[0] == 0]
            if empty:
                out.append(f"  ** EMPTY datasets: {', '.join(empty)}")
        out.append("")
    return "\n".join(out), n_err, n_warn


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 on warnings/suspicious notes")
    ap.add_argument("--max", type=int, default=15,
                    help="max messages listed per type per program")
    a = ap.parse_args()
    report, n_err, n_warn = check(a.log, a.max)
    print(report)
    if n_err:
        return 2
    return 1 if (a.strict and n_warn) else 0


if __name__ == "__main__":
    sys.exit(main())
