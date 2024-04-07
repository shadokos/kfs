CI ?= false

ifeq ($(CI),true)
    BUILD_ARGS := -Dci=true -Diso_dir=./CI/iso $(BUILD_ARGS)
endif

.PHONY: ci
ifeq ($(MAKELEVEL), 0)
ci:
	$(MAKE) DOCKER=true CI=true ci --no-print-directory
else
ci: debug
	bash CI/run_ci.sh
endif