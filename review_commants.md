# Review: `rtl_unit` Copier Template, `_claude` variant, and `asic_flow/.claude` scaffolding

Reviewer perspective: experienced ASIC designer. Scope: `/prj/dyumnin_projects/copier/rtl_unit/`,
`/prj/dyumnin_projects/copier/_claude/`, and `/prj/ai/asic_flow/.claude/` (Part B).
Date: 2026-07-07.

## Executive summary

The template covers an impressively broad flow (CSR → BSV RTL → lint → sim → formal →
synth → STA → power → PnR → DRC → FPGA → doc → CI), but **a freshly generated project
cannot run most of it out of the box**. Several flows have genuine bugs (formal file-name
mismatch, Yosys script invoked in the wrong mode, missing `dfflibmap`, testbench that
imports a missing test module and uses a removed cocotb API), and every `make` target that
pipes through `tee` reports success even when the tool fails — which silently defeats the
whole CI. Separately, `_subdirectory: .` causes template-repo housekeeping files
(`main.py`, `bean.log`, `uv.lock`, `README.md.orig`, the template's own `README.md`) to be
copied into every generated project.

The `_claude/` directory is a second, divergent, SystemVerilog-centric template with some
genuinely better ideas (input validation, computed SDC budgets, tool-availability probing,
a real CSR example RDL). It should be mined for those ideas and then deleted — two
templates will drift.

---

## 1. Template hygiene / `copier.yml`

1.1 **`_subdirectory: .` copies repo junk into generated projects.** `main.py` (uv
"hello world" leftover), `bean.log` (empty), `README.md.orig`, `uv.lock`,
`.python-version`, and the template's own `README.md` all get copied verbatim. Worse,
`README.md` and `README.md.jinja` both exist, so the rendered README and the copied one
collide. Add them to `_exclude` (along with `copier.yml` itself if not already implied,
`LICENSE` — see 1.5 — and `review_commants.md`).
jvs: the readme conflict is not a problem, readme.md is for teh copier template, readme.md.jinja is for the generated ip

1.2 **Unused questions.** `bus_protocol`, `target_process`, `liberty_file`, `lef_file`,
and `fpga_part` are asked but never referenced by any `.jinja` file:
- `bus_protocol`: `bsv/{{ip_name}}.bsv.jinja` hardcodes an AXI4 xactor and
  `systemrdl/Makefile.jinja` hardcodes `--cpuif axi4-lite-flat`. Either wire the answer
  through (conditional cpuif + BSV interface) or drop the question.
- `liberty_file`/`lef_file`: synth/STA/power/PnR hardcode `$(PDK_ROOT)/lib/typical.lib`
  and `$(PDK_ROOT)/lef/{tech,cells}.lef` instead. Wire the answers in as defaults.
- `fpga_part`: `fpga/Makefile.jinja` hardcodes `xc7a35tcpg236-1`; should be
  `{{ fpga_part }}`. jvs:fix both.
- `target_process`: only appears in a commented-out line of `.autoenv.zsh.jinja`;
  `drc/` hardcodes `sky130A.tech` regardless of the answer. jvs: uncomment in autoenv and use the variable instead of hardcoding.

1.3 **No `ip_name` validation.** `_claude/copier.yml` has a snake_case validator —
adopt it. Also note `| capitalize` lowercases everything after the first letter
(`myIP` → `Myip`), and the ROOT environment variable becomes mixed-case
(`$(Myip_ROOT)`). Consider `{{ ip_name | upper }}_ROOT` for the env var and a single
Jinja variable (e.g. set once in each template) instead of repeating the filter
expression ~40 times. jvs: agreed on the env variable fix it. use the validator.

1.4 **`_exclude` of `fpga`/`formal` breaks the top Makefile.** When `enable_fpga` or
`enable_formal` is false the directories are excluded, but the top-level `Makefile`
still runs `$(MAKE) -C fpga clean` / `-C formal clean` unconditionally, and `ci_full`
lists `formal`. `make clean` in such a project fails. The top Makefile must become
`Makefile.jinja` with matching `{% if %}` guards (the `.gitlab-ci.yml.jinja` `formal`
job needs the same guard). jvs: ok fix it.

1.5 **LICENSE is not templated.** Generated projects inherit "MIT ... 2024 dyu-copier
contributors" regardless of `author`/year. Template it, or add a `license` question as
`_claude` does. jvs:ok fix it.

1.6 **README inconsistencies.** Title/usage say `hdl_unit` (`copier copy
gh:dyu-copier/hdl_unit`) while the repo is `rtl_unit`; README says Python >= 3.10 but
`pyproject.toml.jinja` requires >= 3.12; the `cdc/` directory is listed in the structure
but there is no `cdc`/`testplan` entry in the Flows table (and no `cdc` target at all —
see 2.2). jvs: git remote is hdl_unit. local folder name is incorrect. change python version of 3.12

## 2. Top-level `Makefile`

2.1 **Target ordering encodes no real dependencies.** `all: csr rtl lint test synth`
works only serially; `make -j` breaks it, and `ci_quick: lint csr rtl test` runs lint
*before* the Verilog even exists (lint reads `$(ROOT)/verilog/*.v`). Either make the
targets真 prerequisites (`lint: rtl`, `test: rtl`, `synth: rtl`, `rtl: csr`) or reorder
`ci_quick` to `csr rtl lint test`. jvs: set the prerequisites

2.2 **`cdc` is orphaned.** `cdc/` exists with a Makefile, but there is no top-level
`cdc` target, it is not in `ci_full`, not in `clean`, not in `help`, and there is no CDC
job in `.gitlab-ci.yml.jinja`. jvs: add it to both Makefile and gitlab

2.3 **`csr` is invoked twice.** `bsv/Makefile` has its own `rdl:` target calling
`../systemrdl`, and the top Makefile also runs `csr` before `rtl`. Harmless but
redundant; pick one owner (prefer the top level). jvs: bsv owns it If toplevel makefile is running rtl it need not run csr.

2.4 The `Makefile` is not a `.jinja` file, so it can't react to `enable_*` answers
(see 1.4). jvs:fix it

## 3. Exit-status correctness (affects every flow)

3.1 **`tool | tee report` swallows failures.** Every lint/formal/sta/power/pnr/drc
recipe ends in `2>&1 | tee ...`; the recipe's exit status is `tee`'s (always 0). With
`.ONESHELL` + `SHELL := /bin/bash`, add `.SHELLFLAGS := -o pipefail -ec` (or
`set -o pipefail` at the top of each recipe). Right now **CI goes green even when
Verilator/sby/yosys/OpenROAD fail** — this is the single highest-impact fix in the
repo. jvs:fix it

3.2 Verilator/Yosys "success" ≠ clean lint. Consider grepping the report for
`%Warning`/`%Error` counts and failing above a threshold, so lint is a gate rather than
an artifact generator. jvs:ok fix it

## 4. `bsv/`

4.1 **Hardcoded `decode.vcd`** in the perl dump-injection hack — copy-paste from a
different IP. Should be `{{ip_name}}.vcd` at minimum. jvs: ok change it.

4.2 **The dump-injection hack itself is questionable.** Patching `$dumpfile/$dumpvars`
into the *generated Verilog* means the same file is later fed to lint/synth/formal —
which is exactly why `verilator.flags` has to suppress `INITIALDLY`/`STMTDLY`.
Prefer leaving the netlist pristine and dumping waves from the testbench side
(cocotb `WAVES=1` / a small `dump.v` tb-only module / iverilog `-DDUMP`), or guard the
injected block with `` `ifdef SIM_DUMP ``. jvs: agreed move the dumping to tb.v

4.3 The template BSV top (`{{ip_name}}.bsv.jinja`) instantiates
`mkConfigCSR_..._Reg` and an AXI4 **master** xactor but connects nothing: no rules
moving requests from the xactor FIFOs into `csr.write/csr.read` (3-arg write with
strobe, per peakrdl-bsv) and no responses back. As shipped it elaborates a dangling
skeleton. Also double-check the direction: a CSR endpoint is an AXI *slave*; exposing
`Ifc_axi4_master` from the DUT looks inverted (or at least needs a comment explaining
the xactor orientation). Add the minimal request/response rules so a generated project
passes its own smoke test. jvs: see  /prj/ip/claude/hdl-et/ip/xspi/bsv/xspi.bsv  for example hookup for the xactors and csr and implement the minimum set of rules to make this functional

4.4 `TOP_FILE`/`-vdir` depend on `$({{Ip}}_ROOT)` being exported; if `.autoenv.zsh` was
not sourced the recipe does `mkdir -p /verilog` and scatters output. Add a guard:
`ifndef {{Ip}}_ROOT $(error source .autoenv.zsh first) endif`. jvs: ok fix it

4.5 `copy_files` copies only FIFO2/SizedFIFO/BRAM*/FIFO1* primitives. Designs using
RegFile, SyncFIFO, RevertReg, etc. will fail downstream; consider copying the needed
subset detected from bsc output (or the whole `$(BLUESPEC_HOME)/lib/Verilog` into a
separate `bsvlib/` dir excluded from lint). jvs: drop copy_files change scripts to pick files from $BLUESPEC_HOME/...

## 5. `tb/`

5.1 **`make test` fails on a fresh project**: `MODULE=test_default` but no
`test_default.py` is scaffolded — only `env.py`. Ship a minimal `test_default.py.jinja`
(reset + version-register read via the RAL model would be the perfect smoke test). jvs:ok add the missing file.

5.2 **`env.py.jinja` has real Python errors:**
- Mixed tabs and spaces (`self.init_config=...` line is tab-indented) → `TabError` at import.
- `regRead` uses `self.ifc`, but `ifc` is assigned to a *local* variable (`ifc=None`)
  in `__init__` → `AttributeError` the first time a callback fires.
- `rv.integer` is the pre-2.0 `BinaryValue` API; `pyproject.toml.jinja` pins
  `cocotb>=2.0.0`, where handle reads return `LogicArray` (use `int(rv)`). Pick one
  cocotb major version and make template + deps agree.
- Dead `pass` statements after `return`.
jvs: fix all issues

5.3 The `else` branch uses `$({{ip_name}}_ROOT)` (uncapitalized — a different,
undefined variable) and a `someother_verilog/design/` placeholder path; the `stem`
target references `Vcl_id_defines.xml` (copy-paste from a `cl_id` project) and a
hardcoded `/tools/saxon/saxon-he-10.5.jar`. Remove or genuinely parameterize this
block; as-is it's dead weight that will confuse users.
jvs: ok fix it.

5.4 `pyproject.toml.jinja` is missing packages the flow actually calls: the `peakrdl`
CLI core and `peakrdl-cocotb-ralgen` (used by `systemrdl/Makefile` `cocotb_ralgen`
target), plus `pytest`. Also nothing installs a simulator note (icarus default).
jvs: add missing packages.

## 6. `systemrdl/`

6.1 `sed -ie 's/.../'` — GNU sed parses `-ie` as `-i` with backup suffix `e`, leaving a
stray `registers.mde` file. Use `sed -i -e`.
jvs:ok fix it.

6.2 The default RDL only has a Version register. `_claude`'s RDL
(CTRL/STATUS/IRQ_STAT/IRQ_EN with `rw1c`, `hwclr`, commented explanations) is a far
better teaching skeleton — port it (adapted to the `{{Ip}}_Reg` addrmap name the BSV
side expects).
jvs:ok port from .claude
6.3 `version_max`/`version_min` naming: conventional names are `major`/`minor`.
jvs: ok fix it.

## 7. `constraints/` (SDC)

7.1 I/O delays are hardcoded `3.0/0.5 ns` with a comment claiming "30% of clock
period" — only true at 100 MHz. Compute them: the `_claude` SDC does
`expr $CLK_PERIOD * 0.25` — adopt that pattern (Jinja-compute or Tcl-compute).
Same for `set_clock_uncertainty 0.1` (scale with period) and `set_max_transition 0.5`.
jvs: ok fix it

7.2 No `set_false_path -from [get_ports RST_N]` in the ASIC SDC (the FPGA XDC has it).
BSV tops emit `CLK`/`RST_N`; add the reset exception (or, better, a reset synchronizer
note). Also prefer excluding CLK from `all_inputs` rather than assigning it 0 ns input
delay.
jvs: ok fix it.

7.3 No `set_driving_cell` / `set_load` — even commented placeholders (as in `_claude`)
help.
jvs: ok fix it.

## 8. `synth/` (Yosys)

8.1 **Script/driver mismatch — this flow does not run as written.**
`Makefile` passes `-DVERILOG_DIR=... -DTOP_MODULE=...` (Verilog *macros*) and invokes
`yosys -s script`, but `yosys_synth.tcl` contains Tcl (`if {[file exists
$::env(LIBERTY_FILE)]}`) which the native yosys script parser can't execute, and reads
`$::env(LIBERTY_FILE)` which the Makefile never `export`s. Fix: invoke `yosys -c` (Tcl
mode), pass settings as environment variables (`LIBERTY_FILE=$(LIBERTY_FILE) yosys -c ...`),
and drop the `-D` flags.
jvs: ok fix it.

8.2 **No `dfflibmap -liberty` before `abc -liberty`.** Sequential cells never get
mapped to the standard-cell library; the "mapped" netlist keeps internal `$dff` cells.
Insert `dfflibmap -liberty $lib` (and consider using the one-shot `synth -top` macro
pass instead of the manual proc/fsm/memory/techmap sequence — less to maintain).
jvs: ok fix it

8.3 The netlist read includes the injected `$dumpvars` initial block (see 4.2); with
`write_verilog -noattr` it is dropped, but yosys will warn/choke on sim constructs —
another reason to keep dump code out of the netlist.
jvs:we are removing this construct in the rtl generation part and moving it to tb

## 9. `sta/` and `power/`

9.1 `setup:` and `hold:` targets run the identical `run_sta.tcl` and merely tee to
differently named reports — the reports lie about their content. Either pass a mode
variable into the Tcl or drop the two aliases.
jvs: ok. fix it

9.2 `LIB_FILE` is defined in the Makefile but `run_sta.tcl`/`run_power.tcl` hardcode
`$::env(PDK_ROOT)/lib/typical.lib` — the override is dead. Also `$(PDK_ROOT)/lib/typical.lib`
matches no real PDK layout (sky130: `libs.ref/sky130_fd_sc_hd/lib/...`). Wire
`liberty_file` from copier through here (see 1.2).
jvs: ok. fix it

9.3 Power: the VCD is taken from `../tb/$(TOP).vcd`, but the bsv hack names it
`decode.vcd` and cocotb puts it inside `$(tst)_build/`. Three flows, three VCD paths —
none agree. Also note in a comment that RTL-signal VCD annotated onto a flattened
synthesized netlist will have very low match rates; recommend gate-level sim or
`set_power_activity -global` fallback.
jvs: for the time being lets stick to rtlsim, also pick the file generated from cocotb.

9.4 No make-level dependency on the synth netlist: running `make sta` before `make
synth` gives an unhelpful OpenSTA error. Add an existence check or an order-only
prerequisite.
jvs: ok fix it.

## 10. `pnr/` (OpenROAD)

10.1 **No `read_liberty`** — CTS, resizing and `report_power` need liberty. Flow will
error or produce nonsense.
jvs: ok fix it.

10.2 **PDK mixing:** CTS buffers `CLKBUF_X1/X2/X3` are Nangate45 cells while routing
layers `met1..met5` are sky130 names. Parameterize per `target_process` (a small
`pdk/{{target_process}}.mk` or Tcl include with site-specific cell/layer names is the
cleanest).
jvs: ok fix it.

10.3 Missing standard steps: `place_pins`/`io_placer`, PDN (`pdngen`), tapcells,
filler insertion, `repair_design`/`repair_timing`, antenna check — and crucially
**no GDS is ever written**, while `drc/` expects `../pnr/output/$(TOP).gds` (10.4).
Add a KLayout/Magic DEF→GDS step or `write_gds` via the OpenROAD-flow-scripts
approach, or scope this file down honestly to "placement trial" and mark DRC as
depending on a hardened flow.
jvs: ok fix it.

10.4 `detailed_route`/`global_route` option names drift across OpenROAD versions
(`-guide_file` is gone in newer builds); pin a tested OpenROAD version in README/CI
image.
jvs: ok fix it.

## 11. `drc/` and `cdc/`

11.1 DRC consumes a GDS that PnR never produces (see 10.3) — the target can never pass
on a generated project.
jvs: ok fix it.

11.2 `magic -rcfile $(TECH_FILE)` passes a `.tech` file where a magicrc is expected;
use `-T $(TECH_FILE)` (or point `-rcfile` at the PDK's `sky130A.magicrc`). `TECH_FILE`
hardcodes sky130 regardless of `target_process`. Also verify the
`foreach {rule_msg count}` parsing of `drc listall why` — its output is not a flat
{msg count} list in current Magic; the report loop likely mis-parses.
jvs: ok fix it.

11.3 `cdc_check.tcl` is mostly aspirational and contains constructs that cannot run:
`dfflibmap -liberty /dev/null 2>/dev/null` (a shell redirection inside a yosys/Tcl
script), `abc -g AND` after dff mapping, and `select ... t:$_DFF_P_ ...` where Tcl will
try to substitute `$_DFF_P_` as a variable. The final "report" is a static methodology
text, not analysis. Recommendation: replace with the honest minimum — a yosys pass that
dumps `write_json` + a small Python post-processor that groups flops by clock net and
lists cross-domain fan-in — or reduce the target to printing a manual-review checklist.
Since the default template is single-clock, this can be a low-priority stub, but it
should not *pretend* to check CDC.
jvs: ok fix it.

## 12. `formal/`

12.1 **File-name mismatch breaks sby:** `[files]` copies
`../verilog/mk{{Ip}}.v` (so the work-dir file is `mk{{Ip}}.v`) but `[script]` does
`read_verilog -sv {{ip_name}}.v`. `prep` never sees the module. Align the names.
jvs: ok fix it.

12.2 `[files]` lists only the top module; BSV primitives (FIFO2.v, SizedFIFO.v, …) it
instantiates are missing → elaboration fails. Add them (or `read_verilog` the whole
verilog dir).
jvs: ok fix it. Note we are now picking bluespec primitives from $BLUESPEC_HOME area.

12.3 Comment bug: "mode prove — bounded model checking" — in sby, `prove` is
k-induction; `bmc` is the bounded check. Fix the doc text (the `_claude` .sby is
correct here and also sets `multiclock off` — worth copying).
jvs: ok fix it

12.4 The BSV template contains no assertions, so prove/cover have nothing to do;
`bsc -check-assert` only helps if assertions exist. Add one example `dynamicAssert`
or an SVA bind file so the flow demonstrates value.
jvs: ok fix it by adding a SVA bind 

## 13. `fpga/`

Broadly the best-written flow in the repo (clean non-project Tcl, staged stop points,
report set). Remaining nits: `FPGA_PART` should default to `{{ fpga_part }}` (1.2);
`program.tcl` is referenced by the `program` target but not shipped; XDC sets
bitstream `CONFIG_VOLTAGE 3.3`/`CFGBVS VCCO` unconditionally, which errors on
UltraScale parts — guard with a comment.
jvs: ok fix it

## 14. `doc/` and `scripts/`

14.1 `doc/Makefile` hard-depends on `$(HOME)/.pandoc/diagram.lua` and a private
template path — fails on any machine but the author's. Vendor the template/filter into
the project or guard with existence checks.
jvs: add guard. Expectation is user installes these files locally

14.2 `files=` includes `{{ip_name}}.md` (never scaffolded — add
`doc/{{ip_name}}.md.jinja` architecture stub) and `testplan.md`, but
`scripts/gen_testplan.py` hard-exits when `testplan/features/` is missing — and the
template ships no `testplan/` directory at all, so `make doc` (and the top-level `doc:
testplan` dependency) fails on every fresh project. Ship
`testplan/features/example.md.jinja` with one CP entry in the documented format.
jvs: ok fix it

14.3 `doc/refman.md.jinja` is a strong section-by-section datasheet guide — good
content, but as shipped the *guidance* text becomes the project's datasheet. Consider
splitting: `refman_guide.md` (kept as reference) + a skeletal `refman.md.jinja` with
just the headings for authors to fill.
jvs: leave as is.

## 15. Repo config files

15.1 `.pre-commit-config.yaml`: the `args: ['--branch','master',...]` block is attached
to **`check-json`** instead of `no-commit-to-branch` — the branch protection silently
does nothing and check-json gets bogus args. Move it up one hook.
jvs: ok fix it.

15.2 `lint/Makefile` `verible` target references `.verible_lint_rules`, but no such
file exists in `rtl_unit` (a `.verible_lint.rules` lives only in the parent `copier/`
dir); the first invocation's error is discarded by `2>/dev/null; \` and the second run
lints with default rules. Ship the rules file and run verible once, with the config.
jvs: ok fix it.

15.3 `.svls.toml` includes a nonexistent `fpga/verilog` path and leftover
`defines = ["DEBUG","FOO=1"]`.
jvs: ok fix it.

15.4 `.autoenv.zsh.jinja` uses `git rev-parse --show-toplevel`, but copier does not
`git init` the generated project; document the requirement or fall back to
`${0:A:h}`. Hardcoded site paths (`/tools/bsc-2025.01`, `/prj/bsvlib/bdir`) should be
copier questions or documented overrides — same for the identical hardcoding in
`ci/.gitlab-ci.yml.jinja` (use CI/CD variables).
jvs: Hardcoded paths should be environment variable e.g. BLUESPEC_HOME,

## 16. `_claude/` directory

16.1 It is a second, incompatible template (generic SV, different question set,
`flow/` layout) plus a stray `mnt/user-data/outputs/...` tree and a `files.zip` —
clearly an imported AI-session output. Keeping both guarantees drift. Recommendation:
**harvest and delete.** Worth harvesting into `rtl_unit`:
- `copier.yml`: `ip_name` snake_case validator; `license`, `org`, `clock_name`,
  `reset_name`/`reset_active`, `num_clock_domains` questions; conditional defaults
  (`enable_cdc: num_clock_domains > 1`).
- `check_env.sh`: excellent tool-probe script — drop into `scripts/` and add a
  top-level `make check_env` target.
- Top `Makefile.jinja` tool-availability guards (`HAS_YOSYS := $(shell command -v ...)`)
  → graceful `[SKIP]` instead of cryptic command-not-found.
- SDC: percentage-based budgets computed from the period.
- `.sby`: correct mode comments, `multiclock off`, solver selection syntax.
- RDL: the CTRL/STATUS/IRQ register-file example (see 6.2).
- cocotb `test_*.py` skeleton with `reset_dut` helper (fixes 5.1).
jvs: agreed harvest update main templates and delete.

16.2 What *not* to take: the `{{ip_name}}.sv.jinja` hand-written AXI-Lite port list
duplicates what peakrdl-regblock generates — in this BSV-centric template the RTL entry
point should remain the BSV top.

---

# TODO list

## P0 — broken out of the box / silently-green CI
- [x] Add `.SHELLFLAGS := -o pipefail -ec` (or `set -o pipefail`) to every sub-Makefile using `| tee` (§3.1)
- [x] Fix formal: `[script]` vs `[files]` filename mismatch; add BSV primitive .v files; fix prove/bmc comment (§12)
- [x] Fix synth: run `yosys -c`, export env vars instead of `-D`, add `dfflibmap -liberty` (§8)
- [x] Ship `tb/test_default.py.jinja`; fix `env.py.jinja` tabs/spaces, `self.ifc`, cocotb-2.0 API (§5.1–5.2)
- [x] `_exclude` template-repo junk: `main.py`, `bean.log`, `uv.lock`, `README.md.orig`, template `README.md` (§1.1)
- [x] Convert top `Makefile` → `Makefile.jinja`; guard fpga/formal in `clean`/`ci_full`/`help`; fix `ci_quick` ordering (lint after rtl) (§1.4, §2.1)
- [x] pre-commit: move `--branch` args from `check-json` to `no-commit-to-branch` (§15.1)
- [x] Ship `lint/.verible_lint_rules` and fix the double-invocation verible recipe (§15.2)
- [x] `sed -ie` → `sed -i -e` in `systemrdl/Makefile.jinja` (§6.1)
- [x] Ship `testplan/features/` skeleton so `make doc` / `gen_testplan.py` doesn't hard-fail; add `doc/{{ip_name}}.md.jinja` (§14.2)
- [x] Add `peakrdl` + `peakrdl-cocotb-ralgen` + `pytest` to `pyproject.toml.jinja` (§5.4)

## P1 — correctness / wire-through
- [x] Wire `bus_protocol`, `liberty_file`, `lef_file`, `fpga_part`, `target_process` answers into the flows, or delete the questions (§1.2) — liberty/lef/fpga_part/target_process wired; `bus_protocol` deleted 2026-07 (superseded by has_axi_slave/has_axi_master + always-APB CSR bus)
- [x] Add `ip_name` snake_case validator; audit `| capitalize` usage and ROOT var naming (§1.3)
- [x] BSV top: connect xactor ↔ CSR (rules incl. 3-arg strobe write); verify master/slave orientation; parameterize VCD name; guard `$dumpvars` injection or move wave dumping to tb (§4.1–4.3)
- [x] Add `$({{Ip}}_ROOT)`-defined guard with `$(error ...)` in bsv/tb/lint Makefiles (§4.4)
- [x] SDC: compute I/O delays/uncertainty/transition from period; add RST_N false path; exclude CLK from all_inputs (§7)
- [x] PnR: add `read_liberty`, PDN/pins/filler steps, per-PDK CTS buffer + routing-layer parameterization, and a DEF→GDS step so DRC has input (§10)
- [x] DRC: `-T` vs `-rcfile`, per-PDK tech file, verify `drc listall why` parsing (§11.1–11.2)
- [x] STA/power: honor `LIB_FILE` override in Tcl; real setup vs hold modes; unify the VCD name/path across bsv/tb/power; add netlist-exists check (§9)
- [x] Rewrite or honestly stub the Yosys CDC script (current Tcl cannot execute) (§11.3)
- [x] Add top-level `cdc` target + CI job, and include cdc in `clean`/`help` (§2.2)
- [x] Remove/replace dead tb `stem` target (`Vcl_id_defines.xml`, hardcoded saxon jar) and the `someother_verilog` else-branch; fix `$({{ip_name}}_ROOT)` case bug (§5.3)
- [x] Move hardcoded site paths (`/tools/bsc-2025.01`, `/prj/bsvlib`) behind copier questions / CI variables (§15.4)

## P2 — quality / consolidation
- [x] Harvest from `_claude/`: check_env.sh (+ `make check_env`), tool-probe guards, richer RDL example, validator, extra questions, SDC/sby snippets — then delete `_claude/` (incl. `mnt/`, `files.zip`) (§16)
- [x] Template LICENSE (author/year) or add license question (§1.5)
- [x] README: fix `hdl_unit`/`rtl_unit` naming, Python version, add cdc/testplan rows (§1.6)
- [x] Split `doc/refman.md.jinja` into guide + skeleton; vendor pandoc template/filter or guard `$(HOME)/.pandoc` deps (§14.1, §14.3) — guards added + plain-HTML fallback when assets absent (2026-07); guide/skeleton split declined per jvs "leave as is"
- [x] Ship `fpga/program.tcl` or drop the `program` target; `FPGA_PART ?= {{ fpga_part }}` (§13)
- [x] `.svls.toml`: remove `fpga/verilog` path and `DEBUG/FOO` defines (§15.3)
- [x] Add an example assertion (BSV `dynamicAssert` or SVA bind) so formal proves something (§12.4)
- [x] Real make dependencies between stages so `make -j` is safe (§2.1)
- [x] Pin/document tested tool versions (OpenROAD especially) in README/CI image (§10.4)
- [x] Consider a `make smoke` target: generate a project with `copier copy --defaults` into CI and run `ci_quick` — superseded by `.github/workflows/ci.yml` (2026-07): renders all 4 has_axi combos and runs the full flow (80 tests) on every push/PR.

---
---

# Part B — `/prj/ai/asic_flow/.claude` (agents + skills scaffolding)

## Executive summary (Part B)

This is well above the usual quality bar for agent scaffolding: an explicit 8-step DAG
with human approval gates, testplan-before-tests discipline, a "never invent a number/
convention" rule repeated everywhere it matters, model/effort tiering per step with the
rationale written into each agent's description, and BSV/cocotb methodology skills that
are clearly distilled from real project code and real regression failures (the cocotb
gotchas section is excellent). The design intent — humans approve, agents execute, refman
stays in sync — is coherent and consistently enforced.

The main risks are (a) **contract drift between these skills and the `rtl_unit` template
they operate on** — several things the skills assert "already exist and work" are, per
Part A, broken or absent in the template; (b) a few **mechanism-level questions in
`ip-flow`** (state-file write races, subagent-dispatching-subagent, stale `in_progress`
recovery); and (c) a couple of **technical errors inside skill content** that an agent
will faithfully reproduce (the APB read-rule example, the "RO … W1C" contradiction in
csr-convention).

## B1. Skill ↔ template contract drift (highest priority)

B1.1 **`new-ip` depends on a README section that doesn't exist.** The skill's sole
source of truth is the "For AI Agents: Creating a New IP with the rtl_unit Flow" section
of the hdl_unit README, fetched live from GitHub. The local template README
(`rtl_unit/README.md`) has no such section. If the GitHub copy doesn't either, the very
first step of every IP flow dead-ends. Verify the section exists upstream; add it to the
template README (it's the right home for it); and give the skill an offline fallback —
CLAUDE.md already names the local clone path, so "if the fetch fails, read the same
section from the local clone and say you did" is safe and keeps the flow runnable
without network.

B1.2 **APB config bus vs. the template's AXI-only reality.** CLAUDE.md's fixed baseline
and `csr-convention` both mandate an APB config bus + AXI data bus, and the `bluespec`
skill's wiring example drives `csr.write` from an APB transactor. But the template
generates `--cpuif axi4-lite-flat` regblock output and its BSV top instantiates a single
AXI4 xactor — no APB anywhere. One of the two is wrong; either fix the template
(`peakrdl regblock --cpuif apb4-flat`, APB slave xactor in the BSV stub) or fix the
baseline. Right now the `bluespec` agent will be told two contradictory things.

B1.3 **`csr-convention` vs. the template's default RDL.** The convention requires
`ID → INTERRUPT_SET/STATUS/MASK/INTERRUPT → CFG_* → STS_*`, but the template RDL ships a
single register named `Version` — wrong name, wrong content, missing the whole interrupt
block. Every new IP starts life violating the convention its own lint step enforces.
Fix the template RDL to scaffold the convention-compliant skeleton (the `_claude` RDL is
80% of the way there — see Part A §6.2 — it just needs the ordering and naming aligned
to this convention).

B1.4 **`pnr` skill asserts "the synth/pnr/sta/power flow already exists and works."**
Per Part A §§8–10, it does not: yosys is invoked in the wrong mode with unexported env
vars, `dfflibmap` is missing, OpenROAD never reads liberty, and `| tee` masks every
failure. Two consequences for the skill: the flow will fail deep inside tools (exactly
what the skill's own PDK_ROOT guidance tries to avoid), and — worse — because failures
are exit-code-masked, a dutiful agent may find *stale or empty report files* and, per
its instructions, mark PPA "TBD" at best or transcribe garbage at worst. The skill's
"never fabricate a PPA number" rule is the right defense, but strengthen it: **before
extracting PPA, check the tool log for an error-free completion marker, not just the
existence of a report file.** And fix the template flows (Part A P0s) before this skill
is exercised in anger.

B1.5 **`refman`/`cocotb` reference doc-pipeline pieces the template doesn't have.**
`doc/code_coverage.md`, the functional-coverage summary, and their entries in
`doc/Makefile.jinja`'s `files=` list don't exist in the template (its `files=` is
`refman.md {{ip_name}}.md registers.md ai.md testplan.md`, and `{{ip_name}}.md` itself
is never scaffolded — Part A §14.2). The cocotb skill correctly flags this as "a
copier-template change, raise it with the user" — good — but it's been raised now:
track it in the template TODO rather than rediscovering it per-IP.

B1.6 **`cocotb` skill depends on `cocotbext.dyulib.reset` and cocotbext-axi/apb/uart/
i2c**, none of which are in the template's `pyproject.toml.jinja` (Part A §5.4). Add
them (dyulib presumably from an internal index — document where it comes from).

B1.7 **`cocotb` skill describes the `env.py.jinja` stub as "wiring already in place."**
Per Part A §5.2 the actual stub has a `TabError`, a `self.ifc` bug, and a cocotb-1.x
API against a cocotb-2.x pin. The skill's Section 1 description of the stub is what the
stub *should* be — fix the template to match the skill's description.

B1.8 Minor naming drift: the skill set says "rtl_unit flow" while fetching from
`hdl_unit` GitHub URLs, and the template README titles itself `hdl_unit` in an
`rtl_unit` repo. Pick one name.

## B2. `ip-flow` orchestration mechanics

B2.1 **Concurrent writes to `state.yaml`.** The whole point of the DAG is parallel
dispatch (`bluespec` + `testplan` unblock together), and each agent finishes by
rewriting `state.yaml`. Two agents finishing near-simultaneously is a classic
read-modify-write race — one agent's `pending_review` block silently vanishes. Options,
in increasing robustness: (a) instruct agents to re-read the file immediately before
writing and only touch their own step's subtree (helps, doesn't eliminate); (b) one file
per step (`.flow/steps/<step>.yaml`) so writers never collide, with `ip-flow`
assembling the view at Status time; (c) an append-only event log that `ip-flow` folds
into state. Given everything else here is file-based, (b) is the natural fit.
jvs: switch to one file per step.

B2.2 **Sub-agent dispatching sub-agents.** `ip-flow` says step agents invoke `refman`
"via refman-agent directly" as their last action — but the step agents' own files say
"invoke the `refman` *skill*" (inline, in-context). These are different mechanisms with
different consequences: dispatched subagents typically can't spawn further agents, and
an inline skill invocation runs at the *step agent's* model/effort, not refman-agent's
Sonnet/medium tier — so the tiering intent silently doesn't hold for refman when it's
hooked from a Haiku-tier step like `pnr`. Decide which mechanism is real, state it in
both places, and if it's inline-skill, accept (and document) that refman inherits the
caller's tier.
jvs: recommend a fix and implement it.

B2.3 **Stale `in_progress` recovery is unspecified.** If a dispatched agent's session
dies (crash, interrupt, context exhaustion), the step sits `in_progress` forever and
Status just reports "currently running." Add to the Status action: an `in_progress`
step with no live agent is a recoverable state — offer to re-dispatch (agents should be
idempotent against partially-done work; worth one sentence in the shared agent
boilerplate).
jvs: recommend a fix and implement it.

B2.4 **DAG gap: `cocotb` doesn't depend on `bluespec`.** Tests can be *authored*
against spec + testplan without RTL, but they can't *run* — and the cocotb skill's own
Section 6/regression content assumes runnable RTL. Either split the step (author vs.
run) or add the dependency; as wired, `cocotb` can be dispatched right after `testplan`
approval and will block on missing RTL every time, burning a dispatch.
jvs: split authoring and regression.

B2.5 **No verification-closure or lint/formal/CDC steps in the DAG.** The 8 steps end
at `cocotb` (write tests) and `pnr`. Nothing owns: run the full regression, close every
`CP-xx` (`Test:` filled, passing), reach a coverage bar, run `make lint`/`formal`/`cdc`.
The testplan skill's own "Open question" notes closure tracking is unbuilt — but even
without tooling, a human-gated `regression` step between `cocotb` and `pnr` (its
checklist: all checkpoints closed, coverage %, lint clean) would make the DAG reflect
how sign-off actually works. Right now `pnr` can be reached with zero passing tests.
jvs: its ok the human review is supposed to address this and ensure completeness.

B2.6 `open_questions` is a flat string list, but blocked steps reference it. Make
entries `{step, question}` so Action 4 (Resolve) can mechanically find which step to
unblock, instead of inferring from prose.

B2.7 The `owner` field is written at Start and never used by any action. Either use it
(Status grouping, review-request addressing) or drop it.

B2.8 The 8 agent files are 90% identical boilerplate — fine operationally, but the
state-update protocol now lives in 8 copies. When it changes (e.g. per B2.1), one will
be missed. Consider moving the protocol to a single referenced doc (`.flow/PROTOCOL.md`
or a section in ip-flow's SKILL.md) and keeping only the step-specific frontmatter +
"invoke skill X" in each agent file.
jvs: ok fix it.

## B3. Technical errors inside skill content

B3.1 **`bluespec` skill: the APB read rule is protocol-wrong.**
```bsv
rule rl_csr_read(!apb_req.pwrite && apb_req.psel);
```
fires in both the APB setup phase (`psel && !penable`) and the access phase. For any
register with read side-effects (`rclr`, FIFO-backed, interrupt-clear-on-read) that's a
double read; and `csr.read` is an ActionValue so it *is* side-effecting. Guard on
`psel && penable` (matching the write rule) and note the one-cycle pready implication.
An agent will copy this example verbatim into every IP — worth fixing precisely.
jvs:ok fix it.

B3.2 **`csr-convention`: "INTERRUPT_STATUS — RO, sticky, current interrupt bits, W1C"**
— RO and W1C are contradictory. Per the bluespec skill's own field-type table this is
`hw=w, sw=rw, woclr`. Say that (RDL terms), since this file feeds directly into RDL
authoring. Same entry should state whether `INTERRUPT_SET` writes are OR-set
(`woset`-like) or overwrite.
jvs: ok fix it

B3.3 **`bluespec` skill: `namedCall`/`namedCallstmt` use bsc internal APIs**
(`_s__`, `SNamed`, `unS`, `SAction`) — undocumented StmtFSM internals that can break on
a bsc upgrade. Keep them (the waveform-naming payoff is real) but mark them "pinned to
bsc-2025.01, re-verify on toolchain bump" so a future agent doesn't treat compile
failure there as its own bug.
jvs:agreed. 

B3.4 `research` skill: the fixed vendor list ("Synopsys, Cadence, Xilinx, Arm,
Altera") is dated (Xilinx→AMD; Altera re-spun from Intel) and one-size-fits-all
regardless of IP type. Keep a fixed floor but phrase as current entities and allow the
skill to note when a fixed-list vendor is irrelevant for the IP type. Also: governing
specs are often paywalled (IEEE/JEDEC logins) — add one line on what to do when the
spec text is inaccessible (ask the human for the document; never substitute a summary
from memory), consistent with the repo's own "ask for real material" rule.
jvs: agreed. if spec is paywalled ask human to download it and put it in doc/reference folder

B3.5 `spec` skill §5's subsections (command table, frame layouts, rate encoding) are
visibly generalized from one flash/xSPI-class IP. For IPs with no command/opcode
structure (GPIO, timer, PWM, PRCM itself) an agent may pad these with invented content
to satisfy the section map. Add an explicit "mark a subsection N/A when the protocol
has no such concept — an empty section is correct, a fabricated one is not."
jvs :agreed. fix it.

B3.6 `testplan`/`gen_testplan.py` format coupling: the parser requires the literal
em-dash in `## CP-xx — title` and the `# Feature:` prefix. The skill's examples comply,
but a hyphen-minus typed by a human editor silently drops the checkpoint from
`doc/testplan.md`. Either make the regex accept `-|–|—` or have the script error on a
`## CP-` heading it couldn't parse (silent drop is the failure mode to avoid).
jvs: fix the regex

## B4. What's notably good (keep, don't "fix")

- Human approval as the only DAG-advancing action, restated in the skill, the agents,
  and Common Mistakes — the redundancy is the feature.
- Effort tiering with reasons in the agent descriptions (spec/bluespec = Opus because
  errors propagate; csr-convention = Haiku because it's lint). This is the right way to
  spend tokens and it's documented where the dispatcher reads it.
- `cocotb` Section 7 gotchas traced to actual regression reports (the WIP-poll
  SimTimeoutError cluster, the `InterruptEn`→`InterruptRaw` rename fallout) — this is
  exactly what skills are for.
- The testplan checkpoint format (traceable Source field, Test/Coverage filled later,
  `_not yet written_` rendering) is a genuinely sound lightweight vPlan.
- refman's phase→section mapping table and "only revise if the source changed" rule.
- `new-ip`'s "if the fetched instructions changed, stop and tell the user" — the right
  anti-staleness posture (once B1.1 gives it something to fetch).

# TODO list (Part B)

## P0 — the flow will not survive first contact
- [x] Verify/author the "For AI Agents" README section upstream; add local-clone fallback to `new-ip` (B1.1) — README section authored; local-clone fallback in the `new-ip` skill (asic_flow repo) still unverified
- [x] Resolve APB-vs-AXI config-bus contradiction between CLAUDE.md/skills and the template (B1.2) — template now has an always-present APB config/CSR bus (apb4-flat cpuif + APB slave xactor)
- [x] Ship a convention-compliant default RDL (ID + INTERRUPT block) in the template (B1.3)
- [x] Fix the Part-A P0 flow bugs before `pnr`-skill use; add "check tool log for clean completion before extracting PPA" to the pnr skill (B1.4)
- [x] Fix the APB read-rule example in the bluespec skill (`psel && penable`) (B3.1)
- [x] Fix `env.py.jinja` so it matches the cocotb skill's description of it (B1.7 / Part A §5.2)

## P1 — orchestration robustness
- [x] Eliminate the state.yaml write race — per-step state files recommended (B2.1)
- [x] Reconcile refman dispatch mechanism (agent vs. inline skill) across ip-flow and the 8 agent files (B2.2)
- [x] Add stale-`in_progress` recovery guidance to Status (B2.3)
- [x] Add `bluespec` to `cocotb`'s depends_on, or split author/run (B2.4)
- [x] Add a human-gated regression/closure step (and consider lint/formal/cdc) to the DAG (B2.5) — closed per jvs: human review owns closure; the `regression` step supplies the evidence
- [ ] Structure `open_questions` as `{step, question}` (B2.6) — lives in the asic_flow `.claude` repo, not this template; partially mooted by per-step state files
- [x] Fix "RO … W1C" wording in csr-convention with proper RDL access types (B3.2)
- [x] Add cocotbext-* and `cocotbext.dyulib` deps to the template pyproject; document dyulib's source (B1.6)
- [ ] Add coverage docs + `{{ip_name}}.md` to the template doc pipeline that refman/cocotb assume (B1.5) — `{{ip_name}}.md` scaffolded; `doc/code_coverage.md` + functional-coverage summary still missing from `doc/Makefile` `files=`

## P2 — content polish
- [x] Mark `namedCall`/`namedCallstmt` internals as bsc-version-pinned (B3.3)
- [x] Refresh research skill vendor names; add paywalled-spec guidance (B3.4)
- [x] Add "N/A is a valid section state" note to spec §5 subsections (B3.5)
- [x] Make gen_testplan.py tolerant of hyphen variants or fail loudly on unparsed `## CP-` headings (B3.6)
- [x] Deduplicate the 8 agents' state-update boilerplate into one referenced protocol doc (B2.8)
- [ ] Use or drop the `owner` field (B2.7) — lives in the asic_flow `.claude` repo
- [x] Unify `hdl_unit`/`rtl_unit` naming (B1.8) — template CI workflow renamed to hdl_unit (2026-07-15); the `rtl_unit_tools` docker image and `rtl_unit_docker` repo names are intentionally kept

---

# Implementation status (2026-07-07)

All items carrying a `jvs:` directive have been implemented (checked boxes
above), plus the full Part-A P0 set. Verified by rendering the template with
`copier copy --defaults` in both variants (full, and fpga=false/formal=false):
clean Jinja render, no junk files copied, uppercase `<IP>_ROOT` throughout,
`make clean`/`ci_full` parse in both variants, tb python compiles,
`gen_testplan.py` runs against the shipped example checkpoints, and the
generated `.gitlab-ci.yml` parses as YAML. `_claude/` has been harvested
(check_env.sh, validator, RDL skeleton, SDC percentages, sby fixes, cocotb
reset helper) and deleted.

Part B: per-step state files (`.flow/steps/<step>.yaml`) + shared
`agents/PROTOCOL.md`; refman standardized as an inline skill invocation
(tier inheritance documented); stale-`in_progress` recovery added to Status;
cocotb split into authoring (`cocotb`) + execution (`regression`, new agent
+ skill, DAG now 9 steps); bluespec APB read rule fixed (`psel && penable`);
csr-convention rewritten in RDL access terms incl. INTERRUPT_SET OR-set
semantics; bsc-internals pin note; research vendor list refreshed +
paywalled-spec → `doc/reference/` rule; spec §5 N/A note; CLAUDE.md flow
list updated.

Deliberately NOT done (no jvs directive, or explicit "leave as is"):
- `bus_protocol` question still unused (1.2 — no directive). Note the
  systemrdl cpuif is now `apb4-flat` and the BSV top gained an APB config
  bus per the xspi hookup, which supersedes part of this item.
- refman guide/skeleton split (14.3 — "leave as is").
- Verification-closure gating stays with the human reviewer (B2.5 — per
  jvs); the new `regression` step supplies the evidence for that judgment.
- B1.1 ("For AI Agents" README section — needs authoring upstream),
  B2.6 (`open_questions` typing — questions now live per-step, which
  localizes them anyway), B2.7 (`owner` field), B1.5 (coverage docs not yet
  in doc/Makefile `files=`; `{{ip_name}}.md` IS now scaffolded) — left open.

---

# Checklist refresh (2026-07-15)

Boxes above updated after the GitHub Actions template CI went green (80/80,
all 4 has_axi combos, RTL→GDS). Newly closed since 2026-07-07: §1.2
(bus_protocol question deleted), §14.1 (pandoc guards + HTML fallback),
smoke-CI recommendation (superseded by .github/workflows/ci.yml), B1.1
(README agent section authored), B1.2 (APB config bus), B1.3 (convention
RDL), B2.5 (closure owned by human review per jvs), B1.8 (CI workflow
renamed hdl_unit; rtl_unit_tools image name intentionally kept).

Still open:
- B1.5 — coverage docs (`doc/code_coverage.md`, functional-coverage summary)
  not in `doc/Makefile` `files=`.
- B2.6 / B2.7 — `open_questions` typing and `owner` field; both live in the
  asic_flow `.claude` scaffolding repo, not this template.
- new-ip skill's offline local-clone fallback (B1.1 residue, asic_flow repo).
