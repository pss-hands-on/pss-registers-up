# Lab 02 — A randomised single transfer

Branch: `lab02` (holds the lab01 solution). Solution:
`git diff lab02 lab03`.

## Goal

Turn lab01's fixed 16-word copy into one PSS action, `transfer_single`,
whose source address, destination address, length and chunk size are
random fields under constraints. Run it nine times — eight random transfers
and one pinned to the largest unchunked case — and let the bench check every
copy.

## PSS concepts

- `rand` fields on an action: each `do transfer_single` solves them anew.
- `constraint` blocks — named groups of boolean expressions that every
  solution must satisfy.
- `in [a..b]` and `in [x, y, z]` — range and set membership.
- Expressions over several fields: `src + words * 4 <= 0x1000`.
- `repeat (N) { ... }` in an `activity`.
- `do A with { ... }` — add constraints to one traversal only.
- `import target function` — a function the PSS model calls and the bench
  implements (here, the scoreboard check).
- `soft` constraints exist in the LRM, but `pssc` drops them today; every
  constraint in this lab is hard.

## How the check reaches the bench

`lab02_xfer.pss` declares

```
import target function void xfer_done(bit[32] src, bit[32] dst, bit[32] words);
```

`pssc` turns this into a virtual task `xfer_done` on `import_api_if` (the
default body is `$fatal`). `tests/uvm/tests/lab02_xfer_vseq.svh` overrides it
in `lab02_import_api` (a subclass of lab01's `pss_ral_import_api`): it checks
the copy with the scoreboard and then clears the destination window, so the
next transfer cannot pass on stale data. `transfer_single`'s `exec body`
calls `xfer_done(src, dst, words)` once the channel reports done.

## Files

| File | What to do |
|---|---|
| `src/pss/pss_top/actions/lab02_xfer.pss` | `TODO(lab02)`: bodies of `size_c`, `align_c`, `window_c`; the `lab02_xfer` activity |
| `tests/uvm/tests/lab02_xfer_vseq.svh` | given: fills the source window, implements `xfer_done`, calls `ep.lab02_xfer()`; read it |
| `src/pss/flow.yaml`, `tests/uvm/flow.yaml`, `flow.yaml` | already export and run `lab02_xfer` |

`grep -rn 'TODO(lab02)' src tests` lists every place to edit.

## Steps

1. `size_c`: `words` from 1 to 64; `chk` one of 0 (no chunking), 1, 4, 8, 16.
2. `align_c`: `src` and `dst` word-aligned (low two bits zero).
3. `window_c`: `src` in the source window `0x0000..0x0ffc`, `dst` in the
   destination window `0x4000..0x4ffc`, and the whole transfer
   (`words * 4` bytes) inside its window.
4. `lab02_xfer` activity: `repeat (8)` a plain `do transfer_single`, then one
   `do transfer_single with { ... }` that forces `words == 64` and `chk == 0`.
5. Run the check (below).

Read the `exec body` of `transfer_single` as you go: it programs
`ADR0/ADR1/SZ`, enables the done/error interrupt, writes `CSR`, polls, and
calls `xfer_done`.

## Check

```
dfm run tests --tests lab02_xfer -j 1
dfm run smoke -j 1 -u log --report ci-reports/smoke
ci/check-expected.sh
```

Pass: `lab02_xfer` passes, all earlier cases still pass, and
`ci/check-expected.sh` reports "lab looks done". The log shows nine
transfers with different addresses and lengths and no `UVM_ERROR`.

Without the constraints the solver is free to pick any 32-bit address, the
DMA reads or writes outside the bench memory, and the test fails — try it.

## Tool limits

- `soft` is dropped by `pssc`, so there is no "default unless overridden"
  yet; `with` can only narrow what the hard constraints allow.
- No local variables in `exec` bodies (as in lab01): `csr`, `sz`, `polls`
  are action fields.

## Notes

- **CSR read clears ERR.** `CHn_CSR`'s `done`/`err` bits clear on read, so
  the poll loop reads `CSR` once per iteration and tests both bits on that
  one value. Two reads per loop can lose the event.
- **Lengths skew to 64.** The SystemVerilog solver behind `pssc` picks the
  upper bound of `words` more often than a uniform spread would. Count the
  lengths in your log; lab07 (coverage) comes back to this.

## Going further

- Split `transfer_single` into `start`, `probe` and `wait` actions and
  compose them in an activity — the layering later labs build on.
- Add a constraint that keeps source and destination offsets different
  (`src != dst - 0x4000`) and check it holds in the log.
- Run the copies on channel 1 by passing the channel as a field (hint:
  without register-group arrays you need a `match` on `ch0..ch3`).
