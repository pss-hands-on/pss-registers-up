# Lab 01 — Registers

Branch: `lab01` (starts from `main`, i.e. lab00). Solution:
`git diff lab01 lab02`.

## Goal

Describe the wb_dma register map in PSS and drive the DMA with register
reads and writes from a PSS action: check reset values, program channel 0,
start a 16-word copy and poll for completion. In the simulation the vseq's
scoreboard sees the destination memory match the source.

## PSS concepts

- `packed_s<>` struct — a register's field layout, LSB first (`wb_dma_csr_s`,
  `wb_dma_sz_s`).
- `reg_c<T>` — one register; `read()`/`write()` move the whole struct,
  `read_val()`/`write_val()` move the raw word (core library
  `addr_reg_pkg`).
- `reg_group_c` — a block of registers. `get_offset_of_instance()` gives each
  member's byte offset; groups nest (`wb_dma_regs_c` holds `ch0..ch3`).
- `set_handle()` in `exec init_down` — binds the top group to a base address.
- `error()` / `message()` from `std_pkg`.

## How the register access reaches the bus

`pssc` lowers every register access to two import hooks,
`import_api_if.reg_write(addr, data, size)` and `reg_read(addr, output data,
size)`. `tests/uvm/tests/pss_ral_import_api.svh` implements them on the
bench's UVM RAL: it looks the register up with `map.get_reg_by_offset(addr)`
and does a front-door `read`/`write`, so every PSS access is an ordinary
RAL transaction on the Wishbone slave port (trace at `UVM_HIGH`). You do not
edit this file, but read it: it is the whole PSS→UVM register bridge.

## Files

| File | What to do |
|---|---|
| `src/pss/pss_top.pss` | `TODO(lab01)`: add `adr0, am0, adr1, am1, desc, swptr` to `wb_dma_ch_regs_c` and their offset arms |
| `src/pss/pss_top/actions/lab01_regs.pss` | `TODO(lab01)`: AM0 reset check, steps 2, 5 and 6 of the body |
| `src/pss/flow.yaml` | already exports `lab01_regs` |
| `tests/uvm/tests/lab01_regs_vseq.svh` | already fills source memory, calls `ep.lab01_regs()` and checks the copy; read it |
| `tests/uvm/tests/pss_ral_import_api.svh` | the RAL hook (above); read it |

`grep -rn 'TODO(lab01)' src tests` lists every place to edit.

## Steps

1. Open `src/rdl/wb_dma.rdl` and find the channel register block. Add the six
   missing channel registers to `wb_dma_ch_regs_c` as `wb_dma_word_r`, and
   one `match` arm each in `get_offset_of_instance` (0x08 … 0x1c).
2. In `lab01_regs`, check that `CH0_AM0` reads `0xffff_fff0` after reset.
3. Step 2 of the body: write `ADR0 = 0x0000_0000`, `ADR1 = 0x0000_4000`, read
   `ADR1` back, `error()` on a mismatch.
4. Step 5: set `ch_en, inc_src, inc_dst, ine_done, ine_err` in the `csr`
   struct and write it with one `csr.write(csr)`.
5. Step 6: poll `CH0_CSR` until `done` or `err` (at most 10000 reads, one
   read per loop iteration), then `error()` or `message()`.
6. Run the check (below).

## Check

```
dfm run tests --tests lab01_regs -j 1
dfm run smoke -j 1 -u log --report ci-reports/smoke
ci/check-expected.sh
```

Pass: `lab01_regs` passes and `ci/check-expected.sh` reports "lab looks
done". In the log, look for `lab01_regs: CH0 copy done` and no
`UVM_ERROR` from the scoreboard.

## Tool limits

- `pssc` drops local variables declared in an `exec` body, so every value the
  body uses (`csr`, `sz`, `val`, `polls`) is an action field.
- Register-group arrays are not supported: the four channels are `ch0..ch3`,
  not `ch[4]`.

## Note: AM0 reset value

`src/rdl/wb_dma.rdl` gives `CHn_AM0` a reset value of `0xffff_fffc`, but the
RTL resets it to `0xffff_fff0`. The lab checks what the hardware does. A RAL
mirror check against the RDL value would fail on this register.

## Going further

- Program channel 1 as well (offset 0x40) and run both copies one after the
  other.
- Route the interrupt to bank B (`int_msk_b`) and read `int_src_b` after
  completion. Remember the `INT_*` sources are read-clear.
