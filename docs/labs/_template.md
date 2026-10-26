# Lab NN — <title>

Branch: `labNN` (starts from the solution to lab NN-1). Solution:
`git diff labNN labNN+1`.

## Goal

One or two sentences: what the model can do at the end of this lab that it
could not before, and what you see in the simulation.

## PSS concepts

- `<construct>` — what it is for, one line (LRM section).
- …

## Files

| File | What to do |
|---|---|
| `src/pss/…` | `TODO(labNN)`: … |
| `src/pss/flow.yaml` | already exports `<action>` |
| `tests/uvm/tests/<vseq>.svh` | already calls `ep.<action>()`; read it |

`grep -rn 'TODO(labNN)' src tests` lists every place to edit.

## Steps

1. …
2. …
3. Run the check (below).

## Check

```
dfm run tests --tests <case> -j 1
```

Pass: the case passes and `ci/check-expected.sh` reports "lab looks done".
What to look for in the log: …

## Tool limits

What the current `pssc` does not support that this lab would otherwise use,
and how the lab works around it. (`none` if nothing.)

## Going further

Optional extras that are not checked.
