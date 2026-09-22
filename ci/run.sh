#!/usr/bin/env bash
#****************************************************************************
#* ci/run.sh -- the checks CI runs on every commit, on either forge.
#*
#* Both workflow files (.github/workflows/ci.yml, .forgejo/workflows/ci.yml)
#* call this and nothing else to do the work, so what a check IS lives in one
#* place and the two forges cannot drift on it. It runs unchanged on a laptop,
#* which is how it gets debugged.
#*
#*   1. bootstrap -- ivpm into a venv, then `ivpm update` of the dep-set
#*   2. dfm run lint-rtl, dfm run smoke -- each with its own --report bundle;
#*      both always run, so one failing does not hide the other
#*   3. collect   -- the CTRF, JUnit and SARIF files and the report bundles
#*      into $CI_REPORTS, for the reporter and the artifact upload
#*
#* Exit status is nonzero iff either check failed (or bootstrap did).
#*
#* Environment:
#*   CI_DEP_SET   ivpm dep-set to fetch (default: dev-src -- the libraries
#*                from source until their PyPI releases catch up)
#*   CI_REPORTS   where the reports are collected (default: ci-reports)
#*   IVPM_CACHE   ivpm's package cache (default: ~/.cache/ivpm, the path the
#*                workflows cache between runs)
#*   CI_CACHE_DAYS
#*                prune cache entries not linked for this many days
#*                (default: 14; see ci/ivpm-cache-key.sh for why the saved
#*                cache stays fresh enough for this to be safe)
#*   CI_SKIP_BOOTSTRAP=1
#*                use packages/ as it is -- on a laptop that already has it,
#*                this is just the two checks and the reports
#****************************************************************************
set -u -o pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

dep_set="${CI_DEP_SET:-dev-src}"
reports="${CI_REPORTS:-ci-reports}"
export IVPM_CACHE="${IVPM_CACHE:-$HOME/.cache/ivpm}"
mkdir -p "$IVPM_CACHE"

group()    { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }

# ---- 1. bootstrap ----------------------------------------------------------
if [ "${CI_SKIP_BOOTSTRAP:-0}" != "1" ]; then
    group "bootstrap: ivpm update -d $dep_set"
    if ! command -v direnv >/dev/null 2>&1; then
        # packages/packages.envrc is written for direnv (source_env, PATH_add),
        # so the environment a developer gets from `direnv allow` is the one CI
        # gets too.
        sudo=""
        [ "$(id -u)" = "0" ] || sudo="sudo"
        $sudo apt-get update -qq && $sudo apt-get install -y -qq direnv >/dev/null \
            || { echo "::error::could not install direnv"; exit 1; }
    fi
    python3 -m venv .ci-venv \
        && .ci-venv/bin/pip install -q --upgrade pip ivpm \
        || { echo "::error::could not install ivpm"; exit 1; }
    .ci-venv/bin/ivpm --version 2>/dev/null || true
    # -a: clone git URLs as written (HTTPS). A runner has no ssh identity, and a
    # developer's insteadOf rewrite does not exist here anyway.
    .ci-venv/bin/ivpm update -a -d "$dep_set" \
        || { echo "::error::ivpm update -d $dep_set failed"; exit 1; }
    # Drop cache entries no run has linked for a while -- a tool version
    # edapack has moved past -- so the saved cache does not grow without
    # bound. Age is last-LINKED, which this update just refreshed for
    # everything in use.
    .ci-venv/bin/ivpm cache clean --days "${CI_CACHE_DAYS:-14}" \
        || echo "::warning::ivpm cache clean failed; the cache is unchanged"
    direnv allow . || exit 1
    endgroup
fi

# ---- 2. the checks ----------------------------------------------------------
rm -rf "$reports"
mkdir -p "$reports/ctrf"

declare -A status
run_check() {
    local verb="$1"
    group "dfm run $verb"
    direnv exec . dfm run "$verb" -u log --report "$reports/$verb"
    status[$verb]=$?
    endgroup
    # The report, readable in the log on a forge that renders no job summary.
    if [ -f "$reports/$verb/report.md" ]; then
        group "report: $verb (status ${status[$verb]})"
        cat "$reports/$verb/report.md"
        endgroup
    fi
}

run_check lint-rtl
run_check smoke

# ---- 3. collect -------------------------------------------------------------
# Task rundirs are named for the task, not the verb: lint-rtl's work is done by
# this project's `lint` task, and the file names say what each report is.
copy_first() {
    local pattern="$1" dest="$2" f
    f=$(ls -1 $pattern 2>/dev/null | head -1)
    [ -n "$f" ] && cp "$f" "$dest"
}
copy_first "rundir/*/lint-ctrf.json" "$reports/ctrf/lint.json"
copy_first "rundir/*/lint.sarif"     "$reports/lint-rtl/"
copy_first "rundir/*/lint.json"      "$reports/lint-rtl/"
copy_first "rundir/*.smoke/ctrf.json" "$reports/ctrf/smoke.json"
copy_first "rundir/*.smoke/junit.xml" "$reports/smoke/"
copy_first "rundir/*.smoke/report.json" "$reports/smoke/suite.json"

verdict() { [ "${status[$1]}" = "0" ] && echo "pass" || echo "FAIL (status ${status[$1]})"; }

# A job summary where the forge has one. GitHub renders it; Forgejo echoes it
# into the log, which does no harm. Folded, because the CTRF reporter's tables
# are the headline and this is the task-level detail behind them.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    for verb in lint-rtl smoke; do
        {
            echo "<details><summary><code>dfm run $verb</code>: $(verdict $verb)</summary>"
            echo
            cat "$reports/$verb/report.md" 2>/dev/null || echo "_no report written_"
            echo
            echo "</details>"
            echo
        } >> "$GITHUB_STEP_SUMMARY"
    done
fi

echo "lint-rtl: $(verdict lint-rtl)"
echo "smoke:    $(verdict smoke)"
[ "${status[lint-rtl]}" = "0" ] && [ "${status[smoke]}" = "0" ]
