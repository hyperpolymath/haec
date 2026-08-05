#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# Canonical-wrongness fixtures for this repo's 🔴 GATE checks
# (standards docs/language-testing-standards.md R10).
#
# A gate that has never failed is indistinguishable from a gate that CANNOT
# fail. These canaries settle the question: each plants a deliberately-wrong
# input in a scratch tree, runs the gate's own detection logic against it, and
# asserts the gate REJECTS it. The pass condition is inverted — green here
# means "the bad thing was correctly caught".
#
# Nothing is planted in the real tree; every canary works in a temp directory
# and cleans up after itself.
set -uo pipefail

PASS=0; FAIL=0
ok()   { echo "PASS $*"; PASS=$((PASS+1)); }
bad()  { echo "FAIL $*"; FAIL=$((FAIL+1)); }

scratch() { mktemp -d "${TMPDIR:-/tmp}/haec-canary.XXXXXX"; }

# --- canary 1: weak crypto must be rejected -------------------------------
c1() {
  local d; d=$(scratch); trap 'rm -rf "$d"' RETURN
  printf 'fn h() { md5(x) }\n' > "$d/lib.rs"
  local hit
  hit=$(cd "$d" && grep -rE 'md5\(|sha1\(' --include="*.rs" . 2>/dev/null \
        | grep -v 'checksum\|cache\|test\|spec' | head -5 || true)
  if [ -n "$hit" ]; then
    ok "weak crypto (md5) is detected"
  else
    bad "weak crypto NOT detected — the security gate is blind to it"
  fi
}

# --- canary 2: plaintext HTTP must be rejected ----------------------------
# NOTE: the fixture host must avoid every exclusion term the gate applies
# (localhost, 127.0.0.1, example, test, spec). The first version of this canary
# used example.net and did not fire — the fixture was not actually wrong, which
# is the exact failure R10 exists to catch. Kept as a caution.
c2() {
  local d; d=$(scratch); trap 'rm -rf "$d"' RETURN
  printf 'const u = "http://data.internal.invalid/x";\n' > "$d/app.rs"
  local hit
  hit=$(cd "$d" && grep -rE 'http://[^l][^o][^c]' --include="*.rs" . 2>/dev/null \
        | grep -v 'localhost\|127.0.0.1\|example\|test\|spec' | head -5 || true)
  if [ -n "$hit" ]; then
    ok "plaintext HTTP is detected"
  else
    bad "plaintext HTTP NOT detected — the security gate is blind to it"
  fi
}

# --- canary 3: hardcoded secrets must be rejected -------------------------
c3() {
  local d; d=$(scratch); trap 'rm -rf "$d"' RETURN
  printf 'let api_key = "AAAABBBBCCCCDDDDEEEEFFFFGGGG1234";\n' > "$d/cfg.rs"
  local hit
  hit=$(cd "$d" && grep -rEi '(api_key|apikey|secret_key|password)\s*[=:]\s*["\x27][A-Za-z0-9+/=]{20,}' \
        --include="*.rs" . 2>/dev/null | grep -v 'example\|sample\|test\|mock\|placeholder' | head -3 || true)
  if [ -n "$hit" ]; then
    ok "hardcoded secret is detected"
  else
    bad "hardcoded secret NOT detected — the security gate is blind to it"
  fi
}

# --- canary 4: a foreign lock file must be rejected -----------------------
c4() {
  local hit
  hit=$(printf 'package-lock.json\nsrc/main.rs\n' \
        | grep -E 'package-lock\.json|yarn\.lock|Gemfile\.lock|Pipfile\.lock|poetry\.lock|cargo\.lock' || true)
  if [ -n "$hit" ]; then
    ok "foreign lock file is detected"
  else
    bad "foreign lock file NOT detected — the Guix-only gate is blind to it"
  fi
}

# --- canary 5: clean input must NOT be rejected ---------------------------
# Guards the opposite error: a canary suite that always fires proves nothing.
c5() {
  local d; d=$(scratch); trap 'rm -rf "$d"' RETURN
  printf 'fn h() { sha256(x) }\nconst u = "https://ok.invalid/x";\n' > "$d/clean.rs"
  local hit
  hit=$(cd "$d" && grep -rE 'md5\(|sha1\(' --include="*.rs" . 2>/dev/null | head -1 || true)
  if [ -z "$hit" ]; then
    ok "clean input is not falsely rejected"
  else
    bad "clean input WAS rejected — the gate produces false positives"
  fi
}

c1; c2; c3; c4; c5
echo
if [ "$FAIL" -gt 0 ]; then
  echo "gate falsifiability canaries: $PASS/$((PASS+FAIL)) — FAILED"
  echo "A gate whose canary does not fire cannot fail, and is not a gate."
  exit 1
fi
echo "gate falsifiability canaries: $PASS/$PASS"
