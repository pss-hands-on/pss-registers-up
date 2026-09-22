# pss-registers-up

Hands-on lab environment for applying PSS (Portable Test and Stimulus) to a
register-programmed device. The device is the OpenCores WISHBONE DMA/Bridge
engine (`freecores/wb_dma`); the register map is described in SystemRDL and
reaches the testbench as generated code.

What is here today is the starting point the labs build on: the RTL, the
register description, a working UVM regression, and the dv-flow build that ties
them together. The PSS content is added lab by lab.

## Setup

```bash
uvx ivpm update        # fetch tools, the DUT and the VIP into packages/
direnv allow           # put the tools on PATH (IVPM_PACKAGES, the venv, ...)
dfm run tests          # build and run the regression
```

## Running tests

```bash
dfm run tests-info                     # what cases and views exist -- builds nothing
dfm run tests                          # the whole regression (sw_copy, arb, err, pss_hello)
dfm run tests --tests sw_copy          # one case; nothing else is even built
dfm run smoke                          # the quick subset CI runs (sw_copy, pss_hello)
dfm run tests -D build=dbg             # -O0 + waveform tracing
```

`-D build=dbg` leaves a `waves.fst` in each case's rundir, e.g.
`rundir/pss-registers-up.uvm.uvm-tests.sw_copy_0/waves.fst`. Add
`-D hdlsim.vlt.trace_fmt=vcd` for VCD instead.

## Lint

```bash
dfm run lint-rtl                       # Verilator lint of the DUT
dfm run lint -D lint.update_baseline=true   # refresh lint-baseline.json
```

`wb_dma` is unmodified third-party RTL, so its existing findings are accepted in
`lint-baseline.json`; only new findings fail the run.

## CI

Every push and pull request runs `lint-rtl` and `smoke` (the `sw_copy` and
`pss_hello` cases), on both GitHub and the project's Forgejo mirror. Both
forges run the same script, which also runs locally:

```bash
ci/run.sh                        # fresh ivpm venv + `ivpm update -d dev-src`, then both checks
CI_SKIP_BOOTSTRAP=1 ci/run.sh    # just the checks, using the packages/ you already have
```

The reports land in `ci-reports/`: a `dfm --report` bundle per check, the lint
SARIF and JSON, the smoke JUnit, and CTRF for both (`ci-reports/ctrf/`). On
GitHub the CTRF files are rendered into the job summary; on Forgejo, which has
no job summary, the reports are folded into the log and uploaded as an
artifact.

CI builds the dv-flow libraries, pssc and zuspec from source (`dev-src`) until
their PyPI releases catch up with what this project uses.

## Layout

| Path | What |
|---|---|
| `src/pss/` | PSS model (`pss_top.pss`, `pss_top/actions/`), compiled by pssc into the SV the UVM tests call |
| `src/rdl/` | SystemRDL register description -- the source of truth for the register map, and what the UVM RAL is generated from |
| `src/rtl/` | The DUT fileset (the RTL itself is fetched by IVPM into `packages/wb_dma`) |
| `tests/uvm/` | The UVM environment (`env/`), scenarios and tests (`tests/`), and the HDL/HVL tops (`tb/`) |
| `flow.yaml` | The project: it inherits the `project.dv.uvm` archetype from [dv-flow-libproject](https://github.com/dv-flow/dv-flow-libproject) and fills in its slots (`src-rtl`, `tests`, `smoke`, `lint-rtl`) |
| `ci/run.sh`, `.github/workflows/`, `.forgejo/workflows/` | CI (see CI) |
| `lint-baseline.json`, `lint-waivers.yaml` | Accepted DUT lint findings, and waivers (see Lint) |
| `docs/rtl-uvm-tb-design.md` | Why the bench is shaped the way it is -- the device quirks it works around |

## Where this lives

The origin of truth for this repository is Forgejo, not GitHub.

| | |
|---|---|
| Clone (anonymous, read-only) | `https://git.dvkit.org/pss-hands-on/pss-registers-up.git` |
| Issues and pull requests | <https://github.com/pss-hands-on/pss-registers-up> |

## License

Apache-2.0. See [LICENSE](LICENSE).
