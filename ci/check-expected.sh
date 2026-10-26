#!/usr/bin/env bash
#****************************************************************************
#* ci/check-expected.sh -- apply the lab expected-fail list to a CTRF report.
#*
#* On a lab branch (labNN) the lab's own case is wired into the regression but
#* fails until the student finishes the lab. tests/expected-fail.txt names such
#* cases, one per line (`#` starts a comment). This script reads a CTRF report
#* and exits 0 iff every failed case is on that list. A listed case that
#* passes is reported (the lab is done) but is not an error.
#*
#*   ci/check-expected.sh [ctrf.json] [expected-fail.txt]
#*
#* Defaults: rundir/*.smoke/ctrf.json and tests/expected-fail.txt. A missing
#* list means "nothing is expected to fail" (main and `complete`).
#****************************************************************************
set -u -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ctrf="${1:-$(ls "$root"/rundir/*.smoke/ctrf.json 2>/dev/null | head -1)}"
list="${2:-$root/tests/expected-fail.txt}"

[ -n "$ctrf" ] && [ -f "$ctrf" ] || { echo "check-expected: no CTRF report found"; exit 2; }

python3 - "$ctrf" "$list" <<'EOF'
import json, os, sys
ctrf, path = sys.argv[1], sys.argv[2]
expected = set()
if os.path.exists(path):
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if line:
            expected.add(line)
tests = json.load(open(ctrf))["results"]["tests"]
bad = 0
for t in tests:
    name, st = t["name"], t["status"]
    if st == "passed":
        if name in expected:
            print(f"check-expected: {name}: passed (expected-fail; lab looks done)")
    elif name in expected:
        print(f"check-expected: {name}: {st} (expected-fail)")
    else:
        print(f"check-expected: {name}: {st} (UNEXPECTED)")
        bad += 1
print(f"check-expected: {len(tests)} cases, {bad} unexpected failure(s)")
sys.exit(1 if bad else 0)
EOF
