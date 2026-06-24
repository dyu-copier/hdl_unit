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

## License

MIT License. Copyright (c) 2024 dyu-copier contributors.
