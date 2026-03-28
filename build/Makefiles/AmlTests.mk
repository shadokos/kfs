# AML test suite -- compile ASL sources to AML and provide QEMU flags.
#
# Source:  src/drivers/acpi/tests/*.asl
# Output:  zig-out/aml-tests/*.aml
#
# Targets:
#   aml-tests      -- compile all .asl → .aml
#   run-amltest    -- boot QEMU with test SSDTs loaded
#   clean-aml      -- remove compiled AML files

IASL       ?= iasl
AML_SRC    := src/drivers/acpi/tests
AML_OUT    := zig-out/aml-tests

ASL_SRCS   := \
	$(AML_SRC)/ops.asl \
	$(AML_SRC)/test_arith.asl \
	$(AML_SRC)/test_conv.asl \
	$(AML_SRC)/test_data.asl \
	$(AML_SRC)/test_flow.asl \
	$(AML_SRC)/test_hw.asl \
	$(AML_SRC)/test_logic.asl \
	$(AML_SRC)/test_method.asl \
	$(AML_SRC)/test_names.asl \
	$(AML_SRC)/test_ns.asl \
	$(AML_SRC)/test_store.asl \
	$(AML_SRC)/test_compare.asl \
	$(AML_SRC)/test_ref2.asl \
	$(AML_SRC)/test_field2.asl

AML_OBJS   := $(patsubst $(AML_SRC)/%.asl,$(AML_OUT)/%.aml,$(ASL_SRCS))

# QEMU -acpitable flags (one per .aml file).
QEMU_AML_FLAGS := $(foreach f,$(AML_OBJS),-acpitable file=$(f))

# --- rules ---

$(AML_OUT):
	mkdir -p $@

$(AML_OUT)/%.aml: $(AML_SRC)/%.asl | $(AML_OUT)
	$(IASL) -p $@ $<

# Test AML files depend on the ops library source (rebuild if ops changes).
$(filter-out $(AML_OUT)/ops.aml,$(AML_OBJS)): $(AML_SRC)/ops.asl

.PHONY: aml-tests
aml-tests: $(AML_OBJS)

.PHONY: run-amltest
run-amltest: build aml-tests
	qemu-system-i386 -cdrom kfs.iso $(QEMU_AML_FLAGS)

.PHONY: clean-aml
clean-aml:
	rm -rf $(AML_OUT)
