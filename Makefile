# Makefile for UKY CPE 480 (Fall 2020) Assignment 3 - "Pipelined Tangled"

TESTING_DIR = ./testing
TEST_TASMS = $(shell ls $(TESTING_DIR)/*.tasm)
TEST_SIM_OUTPUT_EXTS = .vcd .text.vmem .data.vmem .vvp .vvp.log

DESIGN_DIR = ./src
DESIGN_FILE = $(DESIGN_DIR)/tangled.v
DESIGN_SOURCES = $(shell find $(DESIGN_DIR) -type f)

TASM_SPEC = $(TESTING_DIR)/tangled.aik

NOTES_DIR = ./notes
NOTES_SOURCES = $(shell find $(NOTES_DIR) -type f)
NOTES_PDF = ./notes.pdf

BUNDLE_CONTENTS = $(DESIGN_SOURCES) $(NOTES_PDF) $(NOTES_SOURCES) $(TEST_TASMS) $(TASM_SPEC) Makefile

AIK_DIR = ./aik
AIK_VER = AIK20191030
AIK_URL = http://aggregate.org/AIK/$(AIK_VER).tgz
AIK = $(AIK_DIR)/$(AIK_VER)/aik


# Don't remove test sim intermediate files
# (These should really probably be listed with .SECONDARY as they probably 
# should not be kept upon a failure in generating them. However, .SECONDARY does
# not currently support implicit rules (e.g. %.txt)).
.PRECIOUS: $(addprefix %, $(TEST_SIM_OUTPUT_EXTS))


# Run all testing simulations on the design
.PHONY: sim
sim: $(TEST_TASMS:.tasm=.vcd)


# Run the sim with vvp
%.vcd: %.vvp
	vvp -l $<.log $<


# Compile the design with iverilog
# (First, cd so that readmemh paths are relative to src directory)
%.vvp: $(DESIGN_FILE) $(FRECIP_LOOKUP_FILE) %.text.vmem %.data.vmem
	iverilog -DTEST_TEXT_VMEM=\"$*.text.vmem\" -DTEST_DATA_VMEM=\"$*.data.vmem\" -DTEST_VCD=\"$*.vcd\" -o $@ $(DESIGN_FILE)


# Generate vmem files from tangled assembly
%.text.vmem %.data.vmem: %.tasm $(AIK) $(TASM_SPEC)
	$(AIK) $(TASM_SPEC) $< && \
	mv $*.text $*.text.vmem && \
	mv $*.data $*.data.vmem


# Clean sim outputs
.PHONY: clean
clean:
	- rm -v $(addprefix $(TESTING_DIR)/*, $(TEST_SIM_OUTPUT_EXTS))


# Create TGZ bundle for submission
.PHONY: bundle
bundle: $(BUNDLE_CONTENTS)
	tar -czvf tangled.tgz $(BUNDLE_CONTENTS)


# Compile and download the aik tool as needed
.PHONY: aik
aik: $(AIK)
$(AIK): | $(AIK_DIR)/$(AIK_VER)
	$(MAKE) -C $(AIK_DIR)/$(AIK_VER)

$(AIK_DIR)/$(AIK_VER):
	mkdir -p $(AIK_DIR) && \
	cd $(AIK_DIR) && \
	curl -O '$(AIK_URL)' && \
	tar -xzvf $(AIK_VER).tgz && \
	cd ..


