# PSS hands-on labs

A ladder of labs that builds a PSS model of the wb_dma, from "hello world" up
to a reusable traffic library, and runs it on the UVM bench in this repo.
Each lab adds a little to the last; nothing is thrown away.

| Lab | Branch | Topic | Doc |
|---|---|---|---|
| 00 | `main` | Hello PSS: the PSS → UVM build | [lab00.md](lab00.md) |
| 01 | `lab01` | Registers | lab01.md |
| 02 | `lab02` | A randomised single transfer | lab02.md |
| 03 | `lab03` | Memory as a resource | lab03.md |
| 04 | `lab04` | Channels as resources; concurrency | lab04.md |
| 05 | `lab05` | Interrupts, events and sync | lab05.md |
| 06 | `lab06` | Inference and scenario intent | lab06.md |
| 07 | `lab07` | Coverage closure | lab07.md |
| 08 | `lab08` | Traffic library capstone | lab08.md |
| — | `complete` | All labs solved | — |

Lab docs appear here as each lab is written.

## How the branches work

The branches are stacked. Each one starts from the one before it:

```
main ─► lab01 ─► lab02 ─► … ─► lab08 ─► complete
```

- `main` holds the bench, the hello-world model (lab00) and all lab docs.
- `labNN` holds the solution to lab NN-1 plus the starting point for lab NN:
  stub files marked `// TODO(labNN)`, and the lab's UVM test and regression
  case already wired up.
- `complete` holds the solution to the last lab.

So the solution to a lab is just the difference to the next branch:

```
git diff lab01 lab02          # the solution to lab01
git diff lab01 lab02 -- src/  # only the model
```

Try the lab before you look.

## Doing a lab

```
git switch lab01
grep -rn 'TODO(lab01)' src tests   # what to write
```

Read the lab doc (`docs/labs/lab01.md`), fill in the TODOs, then run the
check. To start a lab over: `git restore .` (or `git switch -f lab01`).
Work on your own branch if you want to keep it: `git switch -c my-lab01 lab01`.

## Checking a lab

Set up the tools once (see the top-level README), then from the repo root:

```
dfm run smoke -j 1 -u log --report ci-reports/smoke
dfm run tests --tests <case>       # just the lab's case
ci/check-expected.sh               # which failures are expected
```

On `labNN` every earlier case passes and the lab's own case fails until you
finish it. That case is named in `tests/expected-fail.txt`, so CI on the lab
branch stays green. When your lab is done, the case passes;
`ci/check-expected.sh` says "lab looks done".

## Conventions (for authors)

- **`TODO(labNN)` markers.** Every place a student must write code has a
  comment `TODO(labNN): <what to do>`. The solution branch has none for that lab.
- **Expected-fail list.** `tests/expected-fail.txt` lists case names (one per
  line, `#` comments) that may fail on this branch: the current lab's case
  only. `main` and `complete` have no list. `ci/run.sh` runs
  `ci/check-expected.sh` after `smoke` and passes CI when every failure is on
  the list. A lab's case is added to the `smoke` list in `flow.yaml` and to
  the case matrix in `tests/uvm/flow.yaml`.
- **Docs are edited only on `main`.** `docs/labs/` reaches the lab branches by
  cascade. A lab branch never touches docs, so cascades do not conflict.
- **Fixes go forward by merge.** Fix the bench or docs on `main`, then run
  `ci/lab-cascade.sh`. It merges `main → lab01 → … → complete` with
  `--no-ff` (never rebase, so existing clones keep working), skips branches
  that don't exist and stops at the first conflict. `BASE=<branch>` changes
  the base.
- **Building a lab.** Write the solution first, on `dev/labNN`. It becomes
  the start of `labNN+1`; strip it back to stubs for `labNN`. Tag release
  points (`labNN-start-v1`) so later fixes do not move what students pinned.
- **CI.** The workflows run on push to every branch (`branches: ['**']`), so
  each lab branch gets CI with no extra matrix: earlier cases must pass, the
  listed case may fail.
- **Tool limits.** Each lab doc lists what the current `pssc` does not yet
  support (e.g. `soft` constraints, address claims, inference, covergroups)
  and how the lab works around it.

New lab docs start from [_template.md](_template.md).
