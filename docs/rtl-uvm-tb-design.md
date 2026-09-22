# Design: plain RTL + UVM testbench for `pss-registers-up`

> **Later changes (2026-09-22).** The local `uvm-dv-project` base described below (§§2, 3, 8 and D2) was
> replaced by the `project.dv.uvm` archetype from dv-flow-libproject and is no longer in the repository.
> Lab 1 added a fourth case (`pss_hello`), so the suite is now 4 tests. The rest of this document is
> kept as the record of the design as built.

**Status:** BUILT. M1–M4 complete; `dfm run tests` is green (3/3). M5 (interrupt-pin monitor) and
the `fw-proto-wb` fw-hdl split (§11) are deferred by decision. Sections below describe the design
as implemented; where reality differed from the proposal it has been corrected in place, and the
differences are listed in §12.
**Reference project:** `~/projects/featherweight-ip/fw-wb-dma` (read-only — nothing there will be touched).

**Provenance:** this environment was ported from `pss-hands-on/pss-wb-dma`, which stood the design
up first; the RDL, the env/tests/tb sources and the base project came over unchanged. Two things
differ here and are described in place: the project-wide `build` variant axis (`-D build=dbg`, §8),
which `pss-wb-dma` does not have, and the `+trace` waveform block in `tb/hvl_top.sv` that it feeds.

---

## 1. Goal and scope

Stand up, in `pss-registers-up`, a **plain RTL + UVM testbench** for the OpenCores `wb_dma` engine:

* DUT = `wb_dma_top` Verilog RTL, from `packages/wb_dma/rtl/verilog` (already fetched).
* Register access = **UVM RAL generated from SystemRDL** (`peakrdl uvm`), driven front-door
  through the `fwvip-wb` initiator agent over a real Wishbone bus.
* Data memories = the two combinational 0-wait-state Wishbone RAMs the reference bench uses.
* Build/run = `dv-flow` (`dfm run tests`), mirroring the reference project's task structure.

**Explicitly out of scope for this pass** (per the request):

* No PSS. Nothing from `src/pss`, `tests/pss`, and no `pssc` / `peakrdl-pss` in the flow.
* No SPL / `fw-hdl` class model of the DMA (`src/spl`, `src/spl-rtl`) — so no TLM view, no
  `wb` (wrapper) view, no SPL-vs-RTL comparator, no `peakrdl-fw-hdl` projection.
* No firmware (`tests/fw`), no `perf` bench, no `uvm-trace` / `fw_dbg` observability plumbing.

The result is deliberately **one DUT view, one build variant** — the reference's `view` × `build`
matrix is what makes its `flow.yaml` large, and none of it earns its keep with a single RTL view.

---

## 2. What the reference does, and why this is a rewrite rather than a copy

The reference **does** have a real RTL view. It runs three DUT views off one env — `tlm` (the SPL
class model *is* the DUT), `wb` (the model inside the `wb_dma_spl` wrapper, over Wishbone), and
`rtl` (the OpenCores `wb_dma_top`) — as the `view` axis of the `sim-img` family. `hdl_top_rtl.sv` /
`hvl_top_rtl.sv` are the RTL cell, and the four "universal" tests run on all three views. So the
RTL bench we want here already exists there, and `hdl_top_rtl.sv` is directly reusable.

What does *not* carry over is the **shape of the env around it**. Two things entangle it:

1. **The env is fw-hdl/SPL-typed.** `wb_dma_env_pkg` imports `wb_dma_spl_pkg`, `fw_hdl_pkg` and the
   generated PSS operation model; every view — RTL included — is published to the config DB as a
   `wb_dma_model_base` subclass (`wb_dma_rtl_model`), and `hvl_top_rtl` builds an
   `fw_component_root` to hold it.
2. **On the RTL view the SPL model is *also* instanced**, as an always-on *passive reference*
   (`refroot`, a `wb_dma_ref_model`) running beside the RTL. That is what the `wb_dma_comparator`
   and the three `wb_monitor_xtor` taps in `hdl_top_rtl` exist to serve: a cross-abstraction
   SPL-vs-RTL check. It is the most valuable thing in that bench — and it is exactly the part that
   cannot come along, because it *is* the SPL model.

And the register front door is **not a UVM RAL at all** — it is the PSS operation model (`wb_dma_c`)
over a `wb_proto_if` seam. The reference's RDL flow emits `fw-hdl` and `pss` projections and
**never `uvm`**.

So: the *tb* layer copies, and the *env* layer is a rewrite — not because the reference lacks an RTL
path, but because dropping both PSS and SPL removes the env's type system (1) and its checker (2).

So the pieces split three ways:

| Reference artifact | Disposition here |
|---|---|
| `src/rdl/*.rdl` | **copy verbatim** — this is the whole point of the exercise |
| `src/rtl/flow.yaml` | **copy verbatim** (already points at `$IVPM_PACKAGES/wb_dma`) |
| `tests/uvm/tb/hdl_top_rtl.sv` | **copy, lightly edited** (drop the SPL-comparison monitors) |
| `tests/uvm/tb/wb_ram_slv.sv` | **copy verbatim** |
| `uvm-dv-project.yaml` + `uvm-dv-project/uvm.yaml` | **copy verbatim** — the `src-rtl` / `tests` project contract and the `dv.uvm.env-base` / `dv.uvm.tb-img` compounds are reusable as-is |
| `tests/uvm/tb/hvl_top_rtl.sv` | **rewrite** — no fw-hdl root, no ref model |
| `tests/uvm/env/*` (22 files) | **rewrite as ~5 files** — RAL-based, no SPL |
| `tests/uvm/tests/*` | **rewrite** — RAL sequences instead of PSS operation calls |
| `src/rdl/flow.yaml` | **rewrite** — `format: uvm` instead of `fw-hdl` + `pss` |
| everything else | omit |

The structure (`src/rdl`, `src/rtl`, `tests/uvm/{env,tests,tb}`, fragment-per-directory
`flow.yaml`, one class per `.svh` included by a thin `*_pkg.sv`) is preserved exactly.

---

## 3. Proposed tree

```
pss-registers-up/
├── flow.yaml                        # NEW  project root: package, imports, fragments
├── uvm-dv-project.yaml              # COPY base project (src-rtl/tests contract, sv-* FileSets)
├── uvm-dv-project/
│   └── uvm.yaml                     # COPY dv.uvm capability pkg (env-base, tb-img, run)
├── docs/
│   └── rtl-uvm-tb-design.md         # this file
├── src/
│   ├── rdl/
│   │   ├── flow.yaml                # NEW  rdl-src + `rdl.Export format: uvm`
│   │   ├── wb_dma.rdl               # COPY verbatim
│   │   └── wb_dma_ch_regs.rdl       # COPY verbatim
│   └── rtl/
│       └── flow.yaml                # COPY verbatim
└── tests/
    └── uvm/
        ├── flow.yaml                # NEW  env lib, sim image, test suite
        ├── tb/
        │   ├── wb_ram_slv.sv        # COPY verbatim
        │   ├── hdl_top.sv           # ADAPTED from hdl_top_rtl.sv
        │   └── hvl_top.sv           # NEW
        ├── env/
        │   ├── wb_dma_env_pkg.sv    # NEW  thin package, ordered `include`s
        │   ├── wb_dma_ral_cfg.svh   # NEW  RAL block + adapter wiring helper
        │   ├── wb_dma_mem_agent.svh # NEW  backdoor over the two wb_ram_slv vifs
        │   ├── wb_dma_scoreboard.svh# NEW  copy check + done accounting
        │   └── wb_dma_env.svh       # NEW  initiator agent + RAL + mem + sb
        └── tests/
            ├── wb_dma_tests_pkg.sv  # NEW
            ├── wb_dma_base_seq.svh  # NEW  RAL helpers: program/arm/await/collect
            ├── wb_dma_base_test.svh # NEW
            ├── wb_dma_sw_copy_seq.svh  / _test.svh   # NEW
            ├── wb_dma_arb_seq.svh      / _test.svh   # NEW
            └── wb_dma_err_seq.svh      / _test.svh   # NEW
```

Files are `COPY` (byte-identical), `ADAPTED` (reference file minus removed features), or `NEW`.

---

## 4. Register model: SystemRDL → UVM RAL

`src/rdl/flow.yaml` becomes a two-task fragment:

```yaml
fragment:
  tasks:
  - name: rdl-src
    uses: std.FileSet
    with:
      type: systemRDLSource
      include: [ wb_dma_ch_regs.rdl, wb_dma.rdl ]     # order matters; not `include

  - export: ral
    uses: rdl.Export
    needs: [rdl-src]
    with:
      format: uvm
      top: wb_dma_regs
      filename: wb_dma_ral_pkg.sv
      args: ["-P", "NUM_CH=4"]
      options:
        type-style: lexical
```

Notes that drove these choices:

* `peakrdl-uvm` derives the **package name from the output file name**, so `wb_dma_ral_pkg.sv`
  gives `package wb_dma_ral_pkg`. It is a real package (`--file-type package`, the default), so
  the env just `import`s it — no include-guard games.
* `-P NUM_CH=4` matches the `.ch_count(4)` on the DUT instance in `hdl_top.sv`. As in the
  reference, **nothing checks that these two agree** — it is a device parameter stated twice. I'll
  put a comment at both sites saying so.
* `type-style: lexical` reuses class definitions, so the four channel banks share one
  `wb_dma_ch_regs` block class and one `wb_dma_csr` reg class.
* Generated shape: `wb_dma_regs` (block) with `csr`, `int_msk_a/b`, `int_src_a/b`, and
  `wb_dma_ch_regs bank[4]`; each bank has `csr`, `sz`, `adr0`, `am0`, `adr1`, `am1`, `desc`,
  `swptr`.

**RAL semantics caveats to design around** (these come straight from the RDL, and are the reason
the bench cannot just trust the mirror):

1. `bank[n].csr.int_err/int_done/int_chk_done` are `rclr` — **a read consumes the event**.
   Every completion check must read `bank[n].csr` **exactly once** and work off that one value.
2. `ch_en` and `stop` are `hwclr` — hardware clears them, so the RAL mirror goes stale.
3. `busy/done/err` are hardware-written status.

Consequence: the env runs the map with **`set_auto_predict(0)`** and the sequences use the
*returned* value of `read()` (`reg.get()` right after) rather than `mirror()`/`get_mirrored_value()`
for anything status-bearing. Configuration registers (`sz`, `adr0`, `am0`, …) are plain `write()`s
and their mirror is fine.

---

## 5. Testbench tops

### `tb/hdl_top.sv` (adapted from the reference `hdl_top_rtl.sv`)

Kept, essentially verbatim — this is the file that encodes the hard-won RTL integration knowledge:

* `wb_dma_top #(.ch_count(4), .pri_sel(2'h2), .ch0..3_conf(4'h1))` — the per-channel `chN_conf[0]`
  "exists" bit and the 8-priority-level selection are both non-obvious and both required.
* The OpenCores port-naming swap (slave/register port carries data on `wb0m_data_*`, master/memory
  port on `wb0s_data_*`) — copied with its explanatory comment intact.
* `wb_initiator_xtor` (from `fw-proto-wb`) on the WB0 slave/register port.
* Two `wb_ram_slv` combinational RAMs on the WB0/WB1 master ports, with their `err` outputs wired
  to the DUT's `wb*_err_i` so error injection can abort a master access.
* Hardware-handshake bus (`dma_req_i` / `dma_nd_i` / `dma_rest_i`) tied off — as in the reference,
  only the non-handshake scenarios run on RTL.
* Clock generator + concurrent reset release (no sim time before `run_test()`).

**Removed:** the three `wb_monitor_xtor` taps and the `fw_clock_xtor_if` instance. Those exist to
feed the SPL-vs-RTL comparator and the fw-hdl model root, neither of which survives here.

**Open question (§9, Q1):** whether to keep the `gpio_monitor_xtor` on `{intb_o, inta_o}`.

### `tb/hvl_top.sv` (new, and much smaller)

```
module hvl_top;
  hdl_top hdl_top();
  initial begin
    // register initiator: bind the vif-based initiator config directly to the
    // xtor's task-API interface (no fw-hdl bridge, no wb_proto_if seam)
    fwvip_wb_initiator_config_p #(virtual wb_initiator_xtor_if #(32,32), 32, 32)::set(
        null, "uvm_test_top.env.m_init*", "cfg", hdl_top.u_host.u_if);
    // data memories: publish the two RAM interfaces for backdoor peek/poke
    uvm_config_db #(virtual wb_ram_slv #(32,32))::set(null, "*", "ram0", hdl_top.u_ram0);
    uvm_config_db #(virtual wb_ram_slv #(32,32))::set(null, "*", "ram1", hdl_top.u_ram1);
    run_test();
  end
  initial begin #5ms; $fatal(1, "[hvl_top] TIMEOUT"); end
endmodule
```

The important simplification versus the reference: it binds
`fwvip_wb_initiator_config_p` (the **virtual-interface** specialization) rather than
`fwvip_wb_initiator_config_ap` (the `wb_proto_if` class-model specialization). That is what lets
the whole `fw-hdl` class layer drop out of the env. `fw-proto-wb`'s transactor modules still
depend on `fw_hdl_pkg` at *compile* time — that dependency stays in the flow, but no bench class
imports it.

No reset agent: the initiator transactor holds during reset, so the first register access simply
waits reset out. (Same reasoning the reference records in `hdl_top_rtl.sv`.)

---

## 6. The env (`tests/uvm/env`)

Five files, one class each, `include`d in dependency order by `wb_dma_env_pkg.sv`:

**`wb_dma_env_pkg.sv`** — imports `uvm_pkg`, `fwvip_wb_xtor_pkg`, `fwvip_wb_pkg`,
`wb_dma_ral_pkg`; declares the shared `SRC_BASE`/`DST_BASE` constants; `include`s the four classes.

**`wb_dma_ral_cfg.svh`** — small builder that `new`s the generated `wb_dma_regs` block, calls
`build()` / `lock_model()`, creates a `fwvip_wb_reg_adapter`, and points `default_map` at the
initiator's sequencer. Also sets `default_map.set_auto_predict(0)` and base address 0 (the
initiator is bound directly at the DUT's register port, so accesses carry raw offsets).

**`wb_dma_mem_agent.svh`** — thin wrapper over the two `virtual wb_ram_slv` handles: `poke`/`peek`
by interface index, plus `fill(if_sel, base, n, seed)` and `inject_err(if_sel, addr)`. This is the
replacement for the reference's `wb_dma_ram_mem` + `fw_mem_if` stack; it is ~40 lines because the
RAM interface already exposes `poke`/`peek`/`inject_err` as functions.

**`wb_dma_scoreboard.svh`** — no bus monitors, no reference model. It compares **memory against
memory** through the backdoor after each transfer (`check_copy(src_if, src, dst_if, dst, n)`) and
counts completions reported by the sequences (`check_done_count`). Holds an `errors` count that
`report_phase` in the base test turns into PASSED/FAILED.

**`wb_dma_env.svh`** — builds `fwvip_wb_initiator m_init`, the RAL config, the memory agent and
the scoreboard; wires the adapter to `m_init.m_seqr` in `connect_phase`.

That is ~250 lines total, against ~1500 in the reference env — the difference is entirely the SPL
model, the PSS adapter, the cross-model comparator and the three DUT flavours.

---

## 7. Sequences and tests

`wb_dma_base_seq` provides the RAL-level device API the scenarios use, and is where every
register-semantics caveat from §4 is handled once:

* `route_interrupts(bank, mask)` — write `int_msk_a`/`int_msk_b`. **Prerequisite**: an unrouted
  channel never appears in `int_src_*`.
* `program_channel(ch, cfg)` — write `sz`, `adr0`, `am0`, `adr1`, `am1` for a channel.
* `arm(ch)` — write `csr` with `ch_en=1` plus the mode/select/increment/priority/`ine_*` bits.
* `await_completion(ch, bank, out status)` — poll `int_src_a/b` (read-only, **no** side effects)
  until the channel's bit sets, then read `bank[ch].csr` **once** and decode `done` / `err` from
  that single value. Returns a `wb_dma_status_e`-style enum so a scenario that errored cannot
  silently pass a "did it interrupt?" check.

Tests, phase 1:

* **`wb_dma_sw_copy_test`** — single-channel block copy, sweeping the four src/dst-interface
  select modes × sizes `{1, 7, 16, 33}` × chunk sizes `{0, 4, 5}`, alternating interrupt bank
  A/B. Per iteration: `mem.fill()` the source, run the sequence, `sb.check_copy()` the
  destination, `sb.check_done_count(1)`. This mirrors the reference's `wb_dma_sw_copy_test`
  one-for-one — same sweep, same assertions — with the PSS calls replaced by RAL calls.

Tests, phase 2 (see §8):

* **`wb_dma_arb_test`** — four channels armed at distinct priorities (`prio` 0–3, which is why
  `pri_sel(2'h2)` is required), asserting all four copies complete correctly. The reference also
  asserts strict-priority *ordering* against its SPL reference model; without a reference model
  here, the ordering claim is dropped and only per-channel data + completion count are checked.
* **`wb_dma_err_test`** — `mem.inject_err()` on a master address, expect the channel to end with
  `err` rather than `done`.

---

## 8. Flow and staging

`flow.yaml` (root) — roughly 40 lines instead of the reference's 180:

```yaml
package:
  name: pss-registers-up
  with: { sim: {type: str, value: vlt} }
  uses: uvm-dv-project
  package-map: packages/dv-flow-package-map.yaml
  imports:
  - uvm-dv-project.yaml
  - rdl
  - fw.proto.wb
  - org.fwvip.wb
  tasks:
  - { override: src-rtl, needs: [rtl] }
  - { override: tests,   needs: [uvm.uvm-tests] }
  - { override: run-lint-rtl, requires: [{std.check.Implemented: {severity: "off"}}] }
  # One holder per (stage, variant); consumers name theirs `flags-<stage>-${{ build }}`.
  - { name: flags-comp-opt, uses: hdlsim.SimCompArgsOpt, with: {sim: "${{ sim }}"} }
  - { name: flags-comp-dbg, uses: hdlsim.SimCompArgsDbg, with: {sim: "${{ sim }}"} }
  - { name: flags-elab-opt, uses: hdlsim.SimElabArgsOpt, with: {sim: "${{ sim }}"} }
  - { name: flags-elab-dbg, uses: hdlsim.SimElabArgsDbg, with: {sim: "${{ sim }}"} }
  - { name: flags-run-opt,  uses: hdlsim.SimRunArgsOpt,  with: {sim: "${{ sim }}"} }
  - { name: flags-run-dbg,  uses: hdlsim.SimRunArgsDbg,  with: {sim: "${{ sim }}"} }
  fragments: [src/rdl/flow.yaml, src/rtl/flow.yaml, tests/uvm/flow.yaml]
```

`tests/uvm/flow.yaml` — one env library, one image, one matrix suite:

* `uvm-env` = `dv.uvm.env-base` with `needs: [ral, rtl, org.fwvip.wb.vip-uvm-hvlsrc, uvm-ram-src, "flags-comp-${{ build }}"]`
* `sim-img` = `dv.uvm.tb-img` with `tb_include: [hdl_top.sv, hvl_top.sv]`, `top: [hvl_top]`,
  and `sim_args: ["+1364-2001ext+v", "--no-assert"]`
* `uvm-tests` = a `matrix:` over the case list, each cell a `hdlsim.vlt.SimUVMCase`

The two `sim_args` are non-negotiable and carry the reference's explanation verbatim: the RTL uses
`int` as a port name (reserved in SV) so the `.v` files must be read as Verilog-2001; and the
design's `// synopsys parallel_case full_case` pragmas, which Verilator uniquely promotes to a
runtime `$stop`, trip spuriously at `t=0` before the first clocked reset load.

**Build order:**

1. ~~**M1** — flow skeleton + RDL→RAL generation.~~ **Done.** `dfm run ral` emits
   `wb_dma_ral_pkg.sv`: `wb_dma_regs` with `bank[4]` submapped at `0x20 + i*0x20`, `int_*` fields
   generated `"RC"`, `ch_en` `"RW"`, `stop` `"WO"` — as designed.
2. ~~**M2** — tops + env elaborate; image builds.~~ **Done.** `dfm run uvm.sim-img`. The only
   Verilator output is pre-existing RTL lint (CASEINCOMPLETE, LATCH) from the OpenCores sources.
3. ~~**M3** — `wb_dma_sw_copy_test` green.~~ **Done.** 4 modes × 4 sizes × 3 chunks = 48
   iterations, 0 errors.
4. ~~**M4** — `arb` + `err`; `dfm run tests` reports the suite.~~ **Done.** 3/3 passed, ~0.7s
   wall, 38.5µs sim.
5. **M5** — swap polled completion for the `fwvip-gpio` interrupt-pin monitor (D1), behind the
   `await_completion()` seam. *Deferred.*

**Negative controls.** A new bench that passes on the first run is the case that most deserves
distrust, so each green result was checked against a deliberate break:

* `arm()` forced to `ch_en=0` → 108 errors, suite red. Confirms the copy comparison and the
  completion wait are both load-bearing, and that the suite gate turns errors into a failure.
* `inject_err()` removed from the error sequence → the channel ends `DONE`, the cause check fires,
  suite red. Confirms `wb_dma_err_test` is not passing vacuously.

Both were reverted and the suite re-verified green.

---

## 9. Decisions (resolved)

**D1 — interrupt observation: poll, don't tap. *Revisit soon.*** Completion is detected by polling
`int_src_a/b` through the RAL, which the RDL guarantees is side-effect-free. No `fwvip-gpio`, no
second VIP. Cost: bus traffic during the wait, and the interrupt *pins* go unobserved.

This is explicitly a "simplest thing first" call, not the end state. `await_completion()` in
`wb_dma_base_seq` is therefore written as **one seam with one implementation**, so swapping in a
pin-edge wait is a body change and not a rewrite of every scenario. Bringing the GPIO monitor back
is: `gpio_monitor_xtor #(2)` on `{intb_o, inta_o}` in `hdl_top.sv` (copy from the reference), an
`org.fwvip.gpio` import, the `fwvip_gpio_monitor_register` macro call in `hvl_top.sv`, and a
subscriber feeding an event that `await_completion()` waits on instead of polling. Call it ~20
lines. **Planned as M5.**

**D2 — copy the `uvm-dv-project` base.** Confirmed. `uvm-dv-project.yaml` + `uvm-dv-project/uvm.yaml`
come across verbatim; `packages/dv-flow-libproject` is an empty checkout and is not used.

**D3 — scoreboard checks memory content + completion counts only.** Accepted as a known reduction
from the reference's SPL-vs-RTL comparator (§2, point 2). Concretely, what is *not* checked here:
per-transaction ordering on the master buses, and strict-priority arbitration order. Recorded in
§10 so it stays a known gap rather than an assumed capability.

**D4 — staged test set.** `sw_copy` is the M3 gate and the primary deliverable; `arb` + `err`
follow at M4 in the same pass. If `sw_copy` turns up RAL-semantics trouble (§4), M4 is the thing
that gets deferred — not the thing that delays M3.

---

## 10. Known gaps / risks

* **`UVM_HOME` — not a gap; withdrawn.** I had this wrong. `hdlsim.vlt.SimLibUVM` checks
  `$UVM_HOME` *first*, but falls back to Verilator's own `share/uvm`, and the edapack Verilator
  build ships it:
  `~/.ivpm/cache/verilator/v5.050_linux_x86_64/share/uvm/src/uvm_pkg.sv`. So nothing needs setting,
  and `.envrc` stays untouched. (`packages/uvm` is present too, via a transitive dep, but the flow
  will not use it unless `$UVM_HOME` points there — worth knowing if the two versions ever differ.)
* **`ivpm.yaml` needs no change for the RTL+UVM path** — `wb_dma`, `fw-proto-wb`, `fwvip-wb`,
  `peakrdl-uvm`, `dv-flow-librdl`, `uvm` and `verilator` are all already fetched under
  `packages/`. `peakrdl-uvm` is present as an installed Python package, which is what
  `rdl.Export format: uvm` shells out to.
* **`packages/dv-flow-libproject` is an empty checkout** (LICENSE + README only). Nothing in this
  design depends on it; noting it because the name suggests otherwise.
* **`NUM_CH=4` is stated twice** (RDL export arg, DUT `ch_count`/`chN_conf` parameters) with
  nothing enforcing agreement — inherited from the reference, called out in comments at both sites.
* **RAL mirror vs. `rclr`/`hwclr` fields** — handled by `auto_predict(0)` + single-read discipline
  (§4). This is the most likely source of a subtle bug; it gets a comment block in
  `wb_dma_base_seq`.
* **No cross-abstraction check (D3).** The reference's strongest assertion — SPL reference model vs.
  OpenCores RTL, compared transaction-by-transaction on the master buses — has no analogue here.
  This bench proves *the copy landed* and *the channel reported done*; it does not prove the engine
  moved the data in the right order, and `arb` cannot assert strict-priority ordering. Accepted, but
  it is the single largest capability difference from the reference.
* **Interrupt pins unobserved (D1).** `inta_o`/`intb_o` are driven by the DUT and read by nobody
  until M5.
* **`fw-hdl` still compiles — see §11.** Not a design constraint of this bench; a packaging issue
  one file wide, in `fw-proto-wb`.

---

## 11. fw-hdl as an opt-in, not a default

Your goal — *protocol kits standalone by default; fw-hdl opt-in, because an unfamiliar library is a
risk people won't take* — is achievable here, and the coupling is much narrower than I first wrote.
I checked the actual imports rather than assuming.

### What is already standalone

`fw-proto-wb` has **deliberately fw-hdl-free exports**, and its own flow file says so:

* `fw.proto.wb.xtor-core` — the three signal-level core modules.
* `fw.proto.wb.xtor-sv` — the three SV interfaces + three integration wrappers
  (`wb_initiator_xtor` and friends). *"Transactor-only exports (no class layer, no fw-hdl) for
  methodology-independent consumers."*
* `fw.proto.wb.checker` — `wb_proto_checker`, explicitly "no package/class-layer/fw-hdl dependency".

So the transactor layer this bench sits on is **already clean**.

### Where the dependency actually enters

Exactly one file: **`wb_mem_adapters.svh`**, included into `fw_proto_wb_pkg`. It provides
`wb_mem_initiator` / `wb_mem_target`, which adapt Wishbone to fw-hdl's protocol-independent
`fw_mem_if`, and therefore pull in `fw_component` / `fw_export` / `fw_std_pkg`. The file's own
header comment concedes the point: *"These re-introduce a dependency on fw-hdl … so the kit's core
transactor layer is no longer fully fw-hdl-free once this file is compiled in."*

Everything else in `fw_proto_wb_pkg` — `wb_proto_if`, `wb_monitor_if`, and the three
`wb_*_xtor_bridge` classes — is fw-hdl-free. That is why `fw.proto.wb.class` carries a
`needs: [fw-hdl.hdl.sv-src]` it would not otherwise need.

And critically: **`fwvip-wb` never touches fw-hdl.** Grepping the VIP's sources, the only symbols it
takes from `fw_proto_wb_pkg` are `wb_proto_if` (in `fwvip_wb_target_config`, which implements it,
and `fwvip_wb_initiator_config_ap`, which holds one). No `fw_mem_if`, no `fw_component`, nothing
else. The VIP is fw-hdl-clean today and merely inherits the dependency through the package it
imports.

### The fix (upstream, small)

Split `wb_mem_adapters.svh` out of `fw_proto_wb_pkg` into its own opt-in package — say
`fw_proto_wb_mem_pkg`, exported as a new `fw.proto.wb.mem` task carrying the
`needs: [fw-hdl.hdl.sv-src]`. Then:

* `fw_proto_wb_pkg` (and `fw.proto.wb.class`) becomes genuinely fw-hdl-free — matching what its
  comments already claim.
* `fwvip_wb_pkg` compiles with no fw-hdl anywhere in the image.
* Consumers who *want* the `fw_mem_if` bridge — the reference project's SPL bench does — add one
  import and opt in.

The only consumer that breaks is one that imports `fw_proto_wb_pkg` and expects `wb_mem_*` to come
with it. In the reference that is `wb_dma_env_pkg`, and the repair is a single added import.

### Recommendation, and what I'd like from you

This is a change to **`fw-proto-wb`, a separate repo** — and note that `packages/` here is an IVPM
checkout, so patching it in place is not durable (`packages/fwvip-wb/flow.yaml` and
`packages/fwvip-gpio/flow.yaml` already carry local patches annotated *"an ivpm re-fetch reverts
this"*). It needs to land upstream to be real.

**I propose we do not block this bench on it.** Nothing in the design above changes either way: we
bind `fwvip_wb_initiator_config_p` (the plain virtual-interface flavour), so no bench class of ours
references fw-hdl regardless — the dependency is purely a compile-time passenger. Landing the split
later removes it silently.

**DECIDED: deferred.** Tracked separately, not part of this pass. The bench is unaffected either
way — no class in `tests/uvm` references fw-hdl, so landing the split upstream later removes a
compile-time passenger and changes nothing here.

---

## 12. Where the build differed from the proposal

Small corrections made while implementing; the sections above reflect the built state.

* **`wb_dma_status_e` moved into `wb_dma_env_pkg`.** Proposed as a sequence-local notion; the
  scoreboard and the tests both name it, so it belongs with the shared declarations.
* **`get_field()` is the status-decode path, and it is a `static` method on `wb_dma_ral_cfg`.**
  The proposal said "use the returned value of `read()`" without saying how. Extracting with
  `f.get_lsb_pos()` / `f.get_n_bits()` off the generated model means the decode restates no bit
  position — the same property the register writes have.
* **The write idiom is `reset()` → `set()` → `write(get())`, never `update()`.** This is the one
  place the RAL semantics bit back, and it is worse than the proposal anticipated. `update()`
  compares desired against a mirror that `hwclr` has already invalidated (hardware cleared `CH_EN`
  at completion, the mirror still reads 1), concludes nothing needs writing, and issues **no bus
  cycle at all** — the channel silently never re-arms. The leading `reset()` also keeps a previous
  read's `BUSY`/`DONE`/`ERR` out of the composed value, since `do_predict` writes read data into
  `desired` as well as `mirrored`.
* **`report_phase` reads the UVM report server**, not just the scoreboard's own counter, so an
  error raised in a sequence (a failed register access, a wrong completion cause) cannot pass
  silently.
* **`arb` asserts completion and per-channel data, not ordering** — as flagged in D3. Each channel
  gets a distinct fill pattern so a crossed address cannot compare equal.
* **`err` is single-iteration by construction.** `wb_ram_slv`'s injected-error arming is sticky
  with no disarm, so a second iteration would inherit the first's fault address.
* **`.gitignore`** gained `packages/` and `rundir/` (present in the reference, missing here).
* **21 `UVM/COMP/NAME` warnings per run are expected.** UVM's component-name check is regex-based
  and degrades without DPI under Verilator, so it flags every component including `uvm_test_top`.
  The reference works around this with a custom `wb_dma_name_check` visitor; that was not carried
  over, since the warnings are inert and the workaround is a fair amount of machinery for cosmetics.
  Worth revisiting if the noise becomes annoying.
