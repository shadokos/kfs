CI ?= false

ifeq ($(CI),true)
    BUILD_ARGS := -Dci=true -Desp_dir=./CI/esp $(BUILD_ARGS)
endif

.PHONY: ci
ifeq ($(MAKELEVEL), 0)
ci:
	$(MAKE) BOOTLOADER=limine CI=true ci --no-print-directory
else
ci: debug
	bash CI/run_ci.sh
endif