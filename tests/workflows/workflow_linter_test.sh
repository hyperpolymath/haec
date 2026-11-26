#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Test: workflow-linter.yml firing and silence.
#
# Runs the real `run:` text of two steps of .github/workflows/workflow-linter.yml
# against fixture workflows and checks that each step
#   * fires (exits non-zero and names the problem) on a bad workflow, and
#   * stays silent (exits zero) on a good one.
# The step text is extracted from the workflow file at run time, so a change to
# the workflow is what is tested, not a copy of it.
#
# Steps covered:
#   "Check SPDX Headers"        (the header comment block is read, not line 1)
#   "Check SHA-Pinned Actions"  (reusable workflow calls must end in @<40 hex>;
#                                its `gh` calls are stubbed, no network is used)
#
# Fixture cases live in tests/workflows/fixtures/workflow-linter/<case>/workflow.yml.
# A case name starting with "spdx-" is run against the SPDX step, one starting
# with "pin-" against the pinning step; "-pass-" cases must exit 0, "-fail-"
# cases must exit non-zero. One extra case runs the pinning step with no `yq` on
# PATH and expects it to fail closed.
#
# Usage: tests/workflows/workflow_linter_test.sh [path/to/workflow-linter.yml]
# Needs: bash, awk, grep, and (for the pin- cases) yq on PATH.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="${1:-$HERE/../../.github/workflows/workflow-linter.yml}"
FIXTURES="$HERE/fixtures/workflow-linter"

[ -f "$WORKFLOW" ] || { echo "workflow not found: $WORKFLOW" >&2; exit 2; }
[ -d "$FIXTURES" ] || { echo "fixtures not found: $FIXTURES" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Print the `run: |` block of the step whose name is $2 in workflow file $1.
extract_step() {
  awk -v want="$2" '
    function indent(s) { match(s, /^ */); return RLENGTH }
    !inrun && $0 ~ /^[[:space:]]*- name:/ {
      n = $0; sub(/^[[:space:]]*- name:[[:space:]]*/, "", n)
      gsub(/^["'\'']|["'\'']$/, "", n)
      found = (n == want); next
    }
    found && !inrun && $0 ~ /^[[:space:]]+run:[[:space:]]*\|[[:space:]]*$/ {
      inrun = 1; base = -1; next
    }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      if (base < 0) base = indent($0)
      if (indent($0) < base) exit
      print substr($0, base + 1)
    }
  ' "$1"
}

extract_step "$WORKFLOW" "Check SPDX Headers" > "$TMP/spdx.sh"
extract_step "$WORKFLOW" "Check SHA-Pinned Actions" > "$TMP/pin.sh"
for s in spdx pin; do
  [ -s "$TMP/$s.sh" ] || { echo "could not extract the $s step from $WORKFLOW" >&2; exit 2; }
done

# `gh` stub: the pinning step installs and runs gh-actions-lock before its own
# check. Those calls are out of scope here and must not touch the network.
mkdir -p "$TMP/stub"
printf '#!/bin/sh\nexit 0\n' > "$TMP/stub/gh"
chmod +x "$TMP/stub/gh"

BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

# run_case <name> <script> <expect: pass|fail> <fixture file> <with-lock: 0|1> [PATH override]
run_case() {
  local name="$1" script="$2" expect="$3" fixture="$4" lock="$5" path_override="${6:-}"
  local work="$TMP/work-$name"
  mkdir -p "$work/.github/workflows"
  cp "$fixture" "$work/.github/workflows/workflow.yml"
  [ "$lock" = 1 ] && : > "$work/.github/workflows/actions.lock"
  local out rc=0
  out="$(cd "$work" && PATH="${path_override:-$TMP/stub:$PATH}" "$BASH_BIN" -e "$TMP/$script" 2>&1)" || rc=$?
  if [ "$expect" = pass ] && [ "$rc" -eq 0 ]; then
    echo "PASS: $name (silent, exit 0)"; PASS=$((PASS + 1))
  elif [ "$expect" = fail ] && [ "$rc" -ne 0 ]; then
    if printf '%s\n' "$out" | grep -q "ERROR"; then
      echo "PASS: $name (fired, exit $rc)"; PASS=$((PASS + 1))
    else
      echo "FAIL: $name exited $rc but printed no ERROR line"; printf '%s\n' "$out" | sed 's/^/    /'
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL: $name expected $expect, exit was $rc"; printf '%s\n' "$out" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

HAVE_YQ=0
command -v yq >/dev/null 2>&1 && HAVE_YQ=1

for dir in "$FIXTURES"/*/; do
  name="$(basename "$dir")"
  case "$name" in
    *-pass-*) expect=pass ;;
    *-fail-*) expect=fail ;;
    *) echo "FAIL: $name: case name must contain -pass- or -fail-"; FAIL=$((FAIL + 1)); continue ;;
  esac
  case "$name" in
    spdx-*) run_case "$name" spdx.sh "$expect" "$dir/workflow.yml" 0 ;;
    pin-*)
      if [ "$HAVE_YQ" = 1 ]; then
        run_case "$name" pin.sh "$expect" "$dir/workflow.yml" 1
      else
        echo "FAIL: $name needs yq on PATH"; FAIL=$((FAIL + 1))
      fi ;;
    *) echo "FAIL: $name: unknown step prefix"; FAIL=$((FAIL + 1)) ;;
  esac
done

# Fail closed: no yq on PATH must be an error, never a silent pass. The PATH
# holds only the stub gh and the tools the step uses, so yq cannot be found.
NOYQ="$TMP/noyq"
mkdir -p "$NOYQ"
cp "$TMP/stub/gh" "$NOYQ/gh"
for tool in grep awk cat sed; do
  src="$(command -v "$tool")" && ln -s "$src" "$NOYQ/$tool"
done
run_case "pin-fail-no-yq-on-path" pin.sh fail "$FIXTURES/pin-pass-sha-and-local/workflow.yml" 1 "$NOYQ"

# A workflow with no actions.lock takes the other branch of the step and must
# not need yq: a clean, inline-pinned workflow is silent there too.
mkdir -p "$TMP/nolock-src"
cat > "$TMP/nolock-src/workflow.yml" <<'YAML'
# SPDX-License-Identifier: MPL-2.0
name: t
on: push
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567
YAML
run_case "pin-pass-no-lockfile-inline-sha" pin.sh pass "$TMP/nolock-src/workflow.yml" 0 "$NOYQ"

echo
echo "workflow-linter fixtures: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
