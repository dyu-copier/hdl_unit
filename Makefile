.PHONY: all csr rtl lint formal test synth sta power pnr drc fpga doc ci_quick ci_full clean help

all: csr rtl lint test synth

csr:
	$(MAKE) -C systemrdl

rtl:
	$(MAKE) -C bsv

lint:
	$(MAKE) -C lint

formal:
	$(MAKE) -C formal

test:
	$(MAKE) -C tb

synth:
	$(MAKE) -C synth

sta:
	$(MAKE) -C sta

power:
	$(MAKE) -C power

pnr:
	$(MAKE) -C pnr

drc:
	$(MAKE) -C drc

# FPGA prototyping (enable_fpga must be true in copier answers)
fpga:
	$(MAKE) -C fpga

doc:
	$(MAKE) -C doc

ci_quick: lint csr rtl test

ci_full: lint csr rtl formal test synth sta power pnr drc

clean:
	$(MAKE) -C systemrdl clean
	$(MAKE) -C bsv clean
	$(MAKE) -C lint clean
	$(MAKE) -C formal clean
	$(MAKE) -C tb clean
	$(MAKE) -C synth clean
	$(MAKE) -C sta clean
	$(MAKE) -C power clean
	$(MAKE) -C pnr clean
	$(MAKE) -C drc clean
	$(MAKE) -C fpga clean
	$(MAKE) -C doc clean

help:
	@echo "Available targets:"
	@echo "  all       - Build CSR, RTL, lint, test, synth (default)"
	@echo "  csr       - Generate CSR register maps (SystemRDL)"
	@echo "  rtl       - Compile RTL (BSV → Verilog)"
	@echo "  lint      - RTL linting (Verilator, Verible, Spyglass)"
	@echo "  formal    - Formal verification (SymbiYosys, JasperGold)"
	@echo "  test      - Run testbench / simulation (cocotb)"
	@echo "  synth     - Logic synthesis (Yosys, DC, Genus)"
	@echo "  sta       - Static timing analysis (OpenSTA, PrimeTime)"
	@echo "  power     - Power analysis"
	@echo "  pnr       - Place & route (OpenROAD, ICC2, Innovus)"
	@echo "  drc       - DRC / LVS checks (Magic, Calibre)"
	@echo "  fpga      - FPGA prototyping (Vivado, Quartus)"
	@echo "  doc       - Generate documentation"
	@echo "  ci_quick  - CI quick check: lint csr rtl test"
	@echo "  ci_full   - CI full flow:   lint csr rtl formal test synth sta power pnr drc"
	@echo "  clean     - Clean all subdirectories"
	@echo "  help      - Show this help message"
