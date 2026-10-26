# Lab 00 — Hello PSS

Branch: `main`. Nothing to write: this lab shows how a PSS action becomes a
task the UVM bench can call. Next: `git switch lab01`.

## Goal

See one PSS action, `entry_a`, compiled to SystemVerilog and run from a UVM
virtual sequence, printing `Hello World!` in the simulation log.

## PSS concepts

- `component` — the static structure of the model. `pss_top` is the root.
- `extend component` — adds to a component declared in another file.
- `action` — a unit of behaviour; `exec body` is what it does when it runs.
- `message(LOW, ...)` — print from the model (from `std_pkg`, hence
  `import std_pkg::*;`).
- Export — which actions the bench may call. Set by the build, not the model.

## Files

| File | What it does |
|---|---|
| `src/pss/pss_top.pss` | declares `component pss_top` |
| `src/pss/pss_top/actions/entry_a.pss` | `extend component pss_top` with `action entry_a` |
| `src/pss/flow.yaml` | the PSS build; `export_action: [entry_a]` makes it callable |
| `tests/uvm/tests/pss_hello_world_vseq.svh` | creates the model and calls `ep.entry_a()` |
| `tests/uvm/flow.yaml` | case matrix; case `pss_hello` runs `pss_hello_world_vseq` |

Layout rule: a component file `X.pss` keeps its extensions in the directory
`X/`, so the build order (extensions before the file they extend) follows
from the layout.

## Steps

1. Read `entry_a.pss`: one action, one `exec body`, one `message`.
2. Read the comment around `export_action` in `src/pss/flow.yaml`. The LRM
   has an `export` statement; `pssc` takes the list from the build instead.
3. Read `pss_hello_world_vseq.svh`: the factory (`pss_top::type_id()`), the
   export API handle `ep`, and the call `ep.entry_a()`.
4. Run the case (below) and find `Hello World!` in its log.
5. Change the message, run again, and see the new text.

## Check

```
dfm run tests --tests pss_hello -j 1
```

Pass: case `pss_hello_1` passes (smoke: `Suite: 2/2 passed`). The log is under
`rundir/` in the case's directory; `grep -r 'Hello World' rundir/*pss_hello*`.

## Tool limits

- `message()` needs `import std_pkg::*;` in the current `pssc`.
- The PSS `export` statement is not acted on; use `export_action:` in the flow.
- Labs to come: no local variable declarations inside `exec` bodies (they are
  dropped); use non-rand action fields instead.

## Going further

Add a second action `entry_b`, add it to `export_action`, and call
`ep.entry_b()` from the vseq.
