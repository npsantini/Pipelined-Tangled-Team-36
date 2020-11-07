# Makefile for UKY CPE 480 (Fall 2020) Assignment 3 - "Pipelined Tangled"

TESTS_BASE_NAMES = testCases
TESTING_DIR = ./testing

SOURCE_DIR = ./src
DESIGN_FILE = $(SOURCE_DIR)/tangled.v
FRECIP_LOOKUP_FILE = $(SOURCE_DIR)/frecipLookup.vmem

TASM_SPEC = $(TESTING_DIR)/tangled.aik

AIK_DIR = ./aik
AIK_VER = AIK20191030
AIK_URL = http://aggregate.org/AIK/$(AIK_VER).tgz
AIK = $(AIK_DIR)/$(AIK_VER)/aik


# Run all testing simulations on the design
.PHONY: sim
sim: $(TESTING_DIR)/$(TESTS_BASE_NAMES:=.vcd)


# Run the sim with vvp
$(TESTING_DIR)/%.vcd: $(TESTING_DIR)/%.vvp
	vvp -l $<.log $<


# Compile the design with iverilog
$(TESTING_DIR)/%.vvp: $(DESIGN_FILE) $(FRECIP_LOOKUP_FILE) $(TESTING_DIR)/%.text.vmem $(TESTING_DIR)/%.data.vmem
	iverilog -DTEST_TEXT_VMEM=\"$(TESTING_DIR)/$*.text.vmem\" -DTEST_DATA_VMEM=\"$(TESTING_DIR)/$*.data.vmem\" -DTEST_VCD=\"$(TESTING_DIR)/$*.vcd\" -o $@ $(DESIGN_FILE)


# Generate vmem files from tangled assembly
$(TESTING_DIR)/%.text.vmem $(TESTING_DIR)/%.data.vmem: $(TESTING_DIR)/%.tasm $(AIK) $(TASM_SPEC)
	$(AIK) $(TASM_SPEC) $<; \
	mv $(TESTING_DIR)/$*.text $(TESTING_DIR)/$*.text.vmem; \
	mv $(TESTING_DIR)/$*.data $(TESTING_DIR)/$*.data.vmem


# Compile and download the aik tool as needed
.PHONY: aik
aik: $(AIK)
$(AIK): | $(AIK_DIR)/$(AIK_VER)
	$(MAKE) -C $(AIK_DIR)/$(AIK_VER)

$(AIK_DIR)/$(AIK_VER):
	mkdir -p $(AIK_DIR); \
	cd $(AIK_DIR); \
	curl -O '$(AIK_URL)'; \
	tar -xzvf $(AIK_VER).tgz; \
	cd ..


