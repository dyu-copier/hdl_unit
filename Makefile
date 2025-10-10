all: csr rtl test synth

csr:
	$(MAKE) -C systemrdl
rtl:
	$(MAKE) -C bsv
test:
	$(MAKE) -C tb
synth:
	$(MAKE) -C synth
