# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Haec (trope front-end) recipes. No Python. Imported by the root Justfile via
#   import? "build/just/trope.just"

# Every example lowers to a well-formed Trope IR document (+ round-trip if the
# sibling trope-checker is checked out/built).
check: haec-examples

haec-examples:
    # justfile_directory() so the recipe is cwd-robust: older just (≤1.32) runs
    # imported recipes from THIS file's directory, newer just from the root.
    bash {{justfile_directory()}}/tests/check-examples.sh
