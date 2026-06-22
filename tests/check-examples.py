#!/usr/bin/env python3
# SPDX-FileCopyrightText: © 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
# SPDX-License-Identifier: MPL-2.0
"""Validate that every Haec example lowers to a well-formed Trope IR document.

Self-contained: validates examples/*.ir.json against the vendored IR contract
(design/trope-ir.schema.json — canonical in trope-checker). The full round-trip
(verdicts via the checker) is a cross-repo integration; run it with a checkout of
the sibling trope-checker (see README). This keeps `just check` green standalone.
"""
from __future__ import annotations
import json, pathlib, sys

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit("error: python 'jsonschema' package is required")

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "design" / "trope-ir.schema.json"
EX = ROOT / "examples"
GREEN, RED, OFF = "\033[32m", "\033[31m", "\033[0m"


def main() -> int:
    v = Draft202012Validator(json.loads(SCHEMA.read_text(encoding="utf-8")))
    manifest = json.loads((EX / "EXAMPLES.json").read_text(encoding="utf-8"))
    by_ir = {e["ir"]: e for e in manifest["examples"]}
    failures = 0
    for path in sorted(EX.glob("*.ir.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        errs = sorted(v.iter_errors(doc), key=lambda e: list(e.absolute_path))
        if errs:
            failures += 1
            print(f"{RED}FAIL{OFF} {path.name}: {errs[0].message} at "
                  f"{'/'.join(str(p) for p in errs[0].absolute_path)}")
        elif path.name not in by_ir:
            failures += 1
            print(f"{RED}FAIL{OFF} {path.name}: not listed in EXAMPLES.json")
        else:
            prog = by_ir[path.name]["program"]
            if not (EX / prog).exists():
                failures += 1
                print(f"{RED}FAIL{OFF} {path.name}: program {prog} missing")
            else:
                print(f"{GREEN}ok{OFF}   {prog} → {path.name} (valid IR, expects {by_ir[path.name]['expect']})")
    print(f"\n{(GREEN+'examples: all lower to valid Trope IR') if not failures else (RED+f'examples: {failures} failure(s)')}{OFF}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
