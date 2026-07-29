#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Every Haec example lowers to a well-formed Trope IR document. Pure bash + jq,
# no Python. Self-contained: structural checks against the vendored IR contract.
# The full round-trip (verdicts) runs when the sibling trope-checker is present.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="$ROOT/examples"
SIB="$ROOT/../trope-checker"
G="\033[32m"; R="\033[31m"; Y="\033[33m"; O="\033[0m"
fail=0
command -v jq >/dev/null || { echo "jq is required"; exit 2; }

# 1. structural: each *.ir.json is well-formed and has the required IR shape.
for f in "$EX"/*.ir.json; do
  if ! jq -e '.version and .profile and .nodes and .edges and .use_model' "$f" >/dev/null 2>&1; then
    echo -e "${R}FAIL${O} $(basename "$f"): not a well-formed Trope IR document"; fail=1
  fi
done

# 2. every example in the manifest pairs a program with its IR.
while read -r e; do
  prog=$(jq -r '.program' <<<"$e"); ir=$(jq -r '.ir' <<<"$e")
  [ -f "$EX/$prog" ] || { echo -e "${R}FAIL${O} missing program $prog"; fail=1; }
  [ -f "$EX/$ir" ]   || { echo -e "${R}FAIL${O} missing IR $ir"; fail=1; }
  [ "$fail" = 0 ] && echo -e "${G}ok${O}   $prog → $ir (well-formed IR, expects $(jq -r '.expect' <<<"$e"))"
done < <(jq -c '.examples[]' "$EX/EXAMPLES.json")

# 3. drift guard: the vendored IR schema must match the canonical one if present.
if [ -f "$SIB/schemas/trope-ir.schema.json" ]; then
  if diff -q "$ROOT/design/trope-ir.schema.json" "$SIB/schemas/trope-ir.schema.json" >/dev/null; then
    echo -e "${G}ok${O}   vendored design/trope-ir.schema.json matches the canonical checker schema"
  else
    echo -e "${R}FAIL${O} vendored IR schema has drifted from trope-checker/schemas/trope-ir.schema.json"; fail=1
  fi
else
  echo -e "${Y}note${O} sibling trope-checker not checked out; skipping schema-drift guard"
fi

# 4. full round-trip: verdicts via the reference checker.
#
# TROPECHECK_BIN names the binary (same variable trope-checker's own conformance
# runner honours); it defaults to the sibling Idris2 reference build. Set
# TROPECHECK_REQUIRED=1 — as CI does — to make a missing binary a hard failure
# rather than a skip: a round-trip that silently does not run is a fake gate.
BIN="${TROPECHECK_BIN:-$SIB/src/idris2/build/exec/tropecheck}"
if [ ! -x "$BIN" ] && [ "${TROPECHECK_REQUIRED:-0}" = "1" ]; then
  echo -e "${R}FAIL${O} TROPECHECK_REQUIRED=1 but no checker binary at $BIN"
  echo "      build it with: idris2 --install verification/proofs/idris2/trope.ipkg"
  echo "                     idris2 --build   src/idris2/tropecheck.ipkg   (Idris2 0.8.0)"
  fail=1
elif [ -x "$BIN" ]; then
  while read -r e; do
    ir=$(jq -r '.ir' <<<"$e"); exp=$(jq -r '.expect' <<<"$e")
    # the checker exits non-zero on p-insufficient — that is a verdict, not an
    # error, so do not let it abort the loop.
    out=$("$BIN" "$EX/$ir" || true)
    got=$(awk '{print $1}' <<<"$out")
    wexp=$(jq -r '.witness // [] | join("/")' <<<"$e")
    ok=1
    [ "$got" = "$exp" ] || ok=0
    if [ -n "$wexp" ]; then
      gw=$(grep -o 'witness=[^[:space:]]*' <<<"$out" | cut -d= -f2)
      gc=$(grep -o 'coord=[^[:space:]]*'   <<<"$out" | cut -d= -f2)
      [ "$gw/$gc" = "$wexp" ] || ok=0
    fi
    if [ "$ok" = 1 ]; then echo -e "${G}ok${O}   round-trip $ir → $got${wexp:+ (witness $wexp)}"
    else echo -e "${R}FAIL${O} round-trip $ir: got '$out', expected $exp${wexp:+ witness $wexp}"; fail=1; fi
  done < <(jq -c '.examples[]' "$EX/EXAMPLES.json")
else
  echo -e "${Y}note${O} no checker binary; skipping verdict round-trip (set TROPECHECK_BIN, or TROPECHECK_REQUIRED=1 to make this fatal)"
fi

if [ "$fail" = 0 ]; then echo -e "\n${G}examples: all lower to valid Trope IR${O}"; else echo -e "\n${R}examples: failures${O}"; fi
exit "$fail"
