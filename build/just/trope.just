# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Haec (trope-particularity front-end) recipes. Imported by the root Justfile via
#   import? "build/just/trope.just"

# Validate that every example lowers to a well-formed Trope IR document.
check: haec-examples

haec-examples:
    python3 tests/check-examples.py

# Full round-trip (verdicts) needs a checkout of the sibling trope-checker.
haec-roundtrip:
    @for f in examples/*.ir.json; do echo "== $f =="; python3 ../trope-checker/src/checker/tropecheck.py "$f" || true; done
