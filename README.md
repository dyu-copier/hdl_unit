# hdl_unit

A [Copier](https://copier.readthedocs.io) template for scaffolding unit-level RTL modules. It generates a standardized project structure covering the full design-to-tape-out workflow: CSR generation, RTL compilation, linting, simulation, formal verification, synthesis, STA, power analysis, place-and-route, DRC/LVS, and optional FPGA prototyping.

## Requirements

- [Copier](https://copier.readthedocs.io) >= 9.x
- Python >= 3.10
- [Bluespec Compiler (bsc)](https://github.com/B-Lang-Org/bsc) - default toolchain for RTL; install expected at `/tools/bsc-2025.01`
- Tool-specific requirements depend on which flows you enable (see [Flows](#flows))

## Usage

```sh
copier copy gh:dyu-copier/hdl_unit <your-module-dir>
```

Copier will prompt for the following:

| Variable | Description | Default |
|---|---|---|
| `ip_name` | Module/IP name | |
| `ip_short_desc` | One-line description | |
| `ip_long_desc` | Extended description | |
| `author` | Author name | |
| `email` | Author email | |
| `target_process` | PDK process node (e.g. `sky130`, `gf180`, `asap7`) | `sky130` |
| `clock_freq_mhz` | Target clock frequency in MHz | `100` |
| `bus_protocol` | Bus interface protocol | `axi4-lite` |
| `enable_fpga` | Include FPGA prototyping flow | `true` |
| `enable_formal` | Include formal verification flow | `true` |
| `fpga_part` | FPGA part number (if FPGA enabled) | `xc7a35tcpg236-1` |
| `liberty_file` | Path to Liberty (.lib) timing library | |
| `lef_file` | Path to LEF technology file | |

**Bus protocol choices:** `axi4-lite`, `axi4`, `ahb`, `apb`, `wishbone`

## Generated Structure

```
<ip_name>/
+-- bsv/            # Bluespec RTL source
+-- synth/          # Logic synthesis
+-- fpga/           # FPGA prototyping (optional)
+-- pnr/            # Place & route
+-- sta/            # Static timing analysis
+-- power/          # Power analysis
+-- tb/             # Simulation testbench (cocotb)
+-- formal/         # Formal verification (optional)
+-- lint/           # Linting
+-- drc/            # DRC / LVS checks
+-- cdc/            # Clock domain crossing checks
+-- doc/            # Documentation
+-- constraints/    # Timing constraints
+-- systemC/        # SystemC models
+-- systemrdl/      # SystemRDL register descriptions
+-- ci/             # CI pipeline scripts
+-- Makefile
+-- pyproject.toml
+-- .autoenv.zsh    # Shell environment (sets ROOT, BLUESPEC_HOME, BSC_PATH)
```

## Flows

All flows are driven from the top-level `Makefile`:

| Target | Description | Tools |
|---|---|---|
| `csr` | Generate CSR register maps | SystemRDL |
| `rtl` | Compile RTL (BSV -> Verilog) | bsc |
| `lint` | Static linting | Verilator, Verible, Spyglass |
| `test` | Simulation / testbench | cocotb |
| `formal` | Formal verification | SymbiYosys, JasperGold |
| `synth` | Logic synthesis | Yosys, Synopsys DC, Cadence Genus |
| `sta` | Static timing analysis | OpenSTA, Synopsys PrimeTime |
| `power` | Power analysis | |
| `pnr` | Place & route | OpenROAD, Synopsys ICC2, Cadence Innovus |
| `drc` | DRC / LVS | Magic, Cadence Calibre |
| `fpga` | FPGA prototyping | Vivado, Quartus |
| `doc` | Generate documentation | |
| `all` | `csr -> rtl -> lint -> test -> synth` | |
| `ci_quick` | `lint -> csr -> rtl -> test` | |
| `ci_full` | Full end-to-end flow | |
| `clean` | Remove all build artifacts | |

Run `make help` inside a generated project for the target reference.

## Updating a Generated Project

To pull in upstream template changes:

```sh
cd <your-module-dir>
copier update
```

## For AI Agents: Creating a New IP with the rtl_unit Flow

When a user asks "create `<foo>` IP using the rtl_unit flow" (e.g. USB, I2C, DMA), follow the steps below in order. Everything you need is in this repository — do **not** re-invent the flow, add build scripts, or edit the template files listed under "Files to leave alone."

### 1. Instantiate the template

Run copier non-interactively into a sibling directory of this template. Substitute the concrete IP name/description; keep `target_process=sky130` and `bus_protocol=axi4-lite` unless the user asked for otherwise.

```sh
copier copy --defaults --trust \
  -d ip_name=<foo> \
  -d ip_short_desc="<one-line summary>" \
  -d ip_long_desc="<paragraph-level summary>" \
  -d author="<user>" \
  -d email="<user@…>" \
  -d target_process=sky130 \
  -d clock_freq_mhz=100 \
  -d bus_protocol=axi4-lite \
  -d enable_fpga=true \
  -d enable_formal=true \
  -d liberty_file="" \
  -d lef_file="" \
  /opt/data/project/rtl_unit \
  /opt/data/project/<foo>
```

Result: `/opt/data/project/<foo>/` populated with all directories from [Generated Structure](#generated-structure). `<foo>` capitalized (`<Foo>`) is used inside the RTL — the wrapper module becomes `mk<Foo>`, the register block becomes `<Foo>_Reg`.

### 2. Files an agent MUST edit (the IP-specific content)

Only these three files carry IP-specific behavior. Everything else is scaffolding.

| File in `<foo>/` | What it defines | What to put in it |
|---|---|---|
| `systemrdl/<foo>.rdl` | Control/Status register map | `addrmap <Foo>_Reg { ... }` — one `reg { field {sw=rw;} <name>[hi:lo]=<reset>; } <REGNAME>;` block per register. `sw=r` for RO, `sw=rw` for R/W, `sw=w` for WO. Address alignment defaults to 4 bytes. The `Version` reg is pre-populated; keep it, add others below. |
| `bsv/<foo>.bsv` | Bluespec RTL top module | Fill in the `mk<Foo>` module body: instantiate submodules for the datapath, write BSV rules that consume `csr` register reads/writes, drive the AXI4 master (`xactor`) when the IP initiates memory transactions, and respond to APB reads/writes (already wired to the CSR block — you usually don't touch APB glue). Keep the interface signature `#(0,32,32,0)` unless integrating a testbench that needs AXI ID (see [Known constraints](#3-known-constraints-do-not-work-around-blindly)). |
| `tb/test_default.py` | cocotb testbench | Add `@cocotb.test()` async functions that use the `RAL` model (already imported) to check register behavior, and drive the design's datapath via `dut.<signal>.value = …`. `test_ral_reset` and `test_ral_fgwr_fgrd` are auto-generated register tests — keep them. |

Optional edits (only if the IP needs it):

| File in `<foo>/` | When to edit |
|---|---|
| `constraints/<foo>.sdc` | If the IP has non-default I/O timing, multiple clock domains, or false paths. The default single-clock 100 MHz constraint is written for you. |
| `doc/refman.md` | Reference manual body (the CSR-map appendix is auto-generated by `make doc`). |
| `formal/<foo>_tb.sv` | Only if you need custom SVA assertions beyond the auto-included ZipCPU protocol checkers. |
| `cdc/cdc_check.tcl` | Only for multi-clock designs — the single-clock default is a no-op. |

### 3. Known constraints — do NOT work around blindly

- **BSV files under `/opt/data/project/bsv_axi/` are read-only.** If a compilation or simulation issue points there, document the bug in `<foo>/doc/bsv_bugs.md`, add a testbench-side workaround in `<foo>/doc/cocotb_workaround.md`, and (only if you must) mark the affected cocotb test as expected-fail. Do not patch anything under `bsv_axi/`.
- **The BSV AXI transactor omits `axi4_awid/arid/bid/rid`** when instantiated with `wd_id=0` (default). cocotbext-axi's `AxiRam` requires those signals and will crash at setup with `AttributeError: 'NoneType' object has no attribute 'value'`. If the IP needs an AXI4 master, either raise `wd_id` in the wrapper interface signature or add a Verilog padding wrapper — see `/opt/data/project/bsv_axi/docs/axi_fixes.md`.
- **APB `PPROT` signal is named `PROT` in BSV** (single P). cocotbext-apb treats it as an optional signal, so setup does not crash, but the driver never binds it. Only fix if the IP relies on protection semantics — same doc for the rename.
- **peakrdl-bsv CSR method signature.** The generated CSR block's `write` method is 3-argument: `write(Bit#(N) addr, Bit#(32) data, Bit#(4) strobe)`. The strobe argument is required — do not drop it.

### 4. Files to leave alone (flow / template infrastructure)

Never edit these unless the user is fixing the template itself. If a flow is broken, fix the root cause in the tool invocation, not in the surrounding scaffolding.

- Every `Makefile` and `*.Makefile.jinja` (bsv, synth, tb, sta, power, drc, cdc, pnr, lint, formal, doc, fpga, systemC, systemrdl, ci, and the top-level `Makefile`)
- Every `*.tcl` and `*.tcl.jinja` (yosys_synth.tcl, cdc_check.tcl, run_sta.tcl, run_power.tcl, magic_drc.tcl, openroad_flow.tcl)
- Every `*.sby` / `*.sby.jinja` and formal harness `*_tb.sv.jinja`
- `pyproject.toml`, `.autoenv.zsh`, `copier.yml`
- `verilog/` (regenerated from BSV every build), `bo/` (BSC binary objects)
- The Docker-based CI: `/opt/data/project/rtl_unit_docker/{Dockerfile,test.sh}`

### 5. Verify

Three options — pick one:

- **Local flow** (fast, needs bsc + peakrdl + verilator + yosys installed):
  ```sh
  cd /opt/data/project/<foo>
  make ci_quick        # lint → csr → rtl → test
  make ci_full         # + synth + sta + power + pnr + drc
  ```

- **Docker flow** (hermetic, mirrors CI, uses `ghcr.io/librelane/librelane:3.0.4` + Bluespec via nix):
  ```sh
  # Edit test.sh IP_DIR / TEMPLATE_DIR paths if <foo> isn't the current test target
  bash /opt/data/project/rtl_unit_docker/test.sh >& /opt/data/project/rtl_unit_docker/err.log
  cat /opt/data/project/rtl_unit_docker/test_summary.txt
  ```

- **GitHub Actions** — the generated IP includes `.github/workflows/ci.yml` (rendered from the template's `.github/workflows/ci.yml.jinja`). Every push and PR runs `make ci_full` inside `ghcr.io/dyu-copier/rtl_unit_tools:latest` against the checked-out IP + a sibling `bsv_axi` repo (assumed `${{ github.repository_owner }}/bsv_axi`). No manual step is needed after `git push` if the repo is on GitHub — check the Actions tab.

A green run reports `run=... pass=21 fail=0 total=21 ... ALL_PASSED` (for `test.sh`) or `━━━ ci_full (RTL → GDS) DONE ━━━` (for `make ci_full`). Individual failing tests print their tail in `test_summary.txt` (docker flow) — read that, not the full `err.log`, as the starting point for triage.

### 6. Reporting back

When the IP is scaffolded and verified, tell the user:
1. Where the new project lives (`/opt/data/project/<foo>/`).
2. Which files you populated (RDL registers, BSV rules, cocotb tests).
3. The final test count from `test_summary.txt`.
4. Any known-failing tests and the reason (link to the `bsv_bugs.md` / `axi_fixes.md` entry you referenced).

Do not restate the template's structure or run steps — the user has read the rest of this README.

## License

MIT License. Copyright (c) 2024 dyu-copier contributors.
