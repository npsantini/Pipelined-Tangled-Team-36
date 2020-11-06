AIK_DIR = ./aik
AIK_VER = AIK20191030
AIK_URL = http://aggregate.org/AIK/$(AIK_VER).tgz
AIK = $(AIK_DIR)/$(AIK_VER)/aik

TASM_SPEC = tangled.aik
TESTS_BASE_NAME = tests


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


.PHONY: test


%.text %.data: %.tasm $(AIK) $(TASM_SPEC)
	$(AIK) $(TASM_SPEC) $<


