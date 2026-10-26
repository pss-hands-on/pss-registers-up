#!/usr/bin/env bash
#****************************************************************************
#* ci/lab-cascade.sh -- carry a fix on the base branch forward through the labs.
#*
#* The lab branches are stacked: main -> lab01 -> lab02 -> ... -> lab08 ->
#* complete. A change made on main (bench, docs) reaches the labs only by
#* merging it forward, one branch at a time. This script does those merges
#* with `git merge --no-ff` (never rebase, so clones students already have
#* keep working). Branches that do not exist yet are skipped. It stops at the
#* first merge that conflicts, leaving that merge in progress to resolve;
#* fix it, commit, and run the script again.
#*
#*   ci/lab-cascade.sh            # main -> ... -> complete
#*   BASE=wpk/x ci/lab-cascade.sh # a different base branch
#*
#* Nothing is pushed. The branch checked out at the start is restored.
#****************************************************************************
set -u -o pipefail

base="${BASE:-main}"
chain=("$base" lab01 lab02 lab03 lab04 lab05 lab06 lab07 lab08 complete)

git diff --quiet && git diff --cached --quiet \
    || { echo "lab-cascade: working tree is not clean"; exit 1; }

start="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"
exists() { git rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }

exists "$base" || { echo "lab-cascade: no base branch '$base'"; exit 1; }

prev="$base"
for br in "${chain[@]:1}"; do
    if ! exists "$br"; then
        echo "lab-cascade: $br does not exist, skipped"
        continue
    fi
    if git merge-base --is-ancestor "$prev" "$br"; then
        echo "lab-cascade: $br already has $prev"
    else
        git switch --quiet "$br" || exit 1
        if ! git merge --no-ff --no-edit -m "Merge $prev into $br (lab cascade)" "$prev"; then
            echo "lab-cascade: CONFLICT merging $prev into $br; resolve, commit, re-run"
            exit 1
        fi
        echo "lab-cascade: merged $prev into $br"
    fi
    prev="$br"
done

git switch --quiet "$start" 2>/dev/null || git checkout --quiet "$start"
echo "lab-cascade: done"
