#!/usr/bin/env bash
# ci/validate.sh - validation contract for DuneAwakening-Wormageddon (workspace rule 24).
# A Windows PowerShell desktop GUI tool: no build/test toolchain, so the gate checks structure,
# secret hygiene, and the invisibility standard. Exit 0 = pass, non-zero = fail; all logic here.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()  { printf '  OK    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "== no active GitHub Actions (rule 24) =="
if [ -d .github/workflows ] && find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print -quit 2>/dev/null | grep -q .; then bad "active .github/workflows YAML exists; retire it"; else ok "no active GHA (lint.yml is retired)"; fi

echo "== required files =="
for f in Wormageddon-GUI.ps1 Wormageddon.ps1 README.md dune-connection.example.json LICENSE; do
  [ -f "$f" ] && ok "$f" || bad "missing $f"
done

echo "== secret hygiene: the real connection file is never committed, the example carries no secret =="
if git ls-files --error-unmatch dune-connection.json >/dev/null 2>&1; then bad "dune-connection.json is TRACKED (must stay gitignored)"; else ok "dune-connection.json not tracked"; fi
if python3 -c 'import json,sys; d=json.load(open("dune-connection.example.json")); sys.exit(0 if d.get("Password","")=="" else 1)'; then ok "example config has empty Password"; else bad "example config ships a non-empty Password"; fi
python3 -m json.tool dune-connection.example.json >/dev/null 2>&1 && ok "example config is valid JSON" || bad "example config is not valid JSON"

echo "== invisibility: no console window at boot/logon/schedule (hub guides/invisibility/) =="
# Run-Console's visible -NoExit window is a reviewed invisibility:allow waiver (a desktop tool the operator runs by hand).
if python3 -I -B ci/check-invisibility.py --root .; then ok "invisibility: no new console-window findings"; else bad "invisibility: new console-window finding(s)"; fi

echo "== self-test: the gate can fail (rule 29) =="
if python3 -c 'import json; json.loads("{bad")' 2>/dev/null; then bad "self-test: invalid JSON was accepted"; else ok "self-test: invalid JSON rejected"; fi

echo
if [ "$fail" -ne 0 ]; then echo "VALIDATE: FAIL"; exit 1; fi
echo "VALIDATE: PASS"
