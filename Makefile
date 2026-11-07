# Bare CUDA Arc — v0 build.
#
# Lane 1 (hardware-free, works on any machine with the SPIR-V toolchain):
#   scan  — portability scanner: nvcc fatbin -> PTX census -> per-target feasibility
#   aot   — PTX -> LLVM IR -> opt -O2 -> llvm-spirv -> SPIR-V binary (.spv),
#           validated by Khronos spirv-val at the target's env + structural checks
#
# Lane 2 (hardware-gated, on the Arc host — auto-skips honestly elsewhere):
#   scripts/verify_arc.sh — live GPU acceptance suites (phase 2)
#
# Target pull-down:
#   make targets        list GPUs
#   make select         interactive pull-down (persists .target)
#   make aot            build + validate for the selected target
#   make aot-all        build for every registered target

include targets/registry.mk

ifneq ($(TARGET),)
ACTIVE_TARGET := $(TARGET)
else ifneq ($(wildcard .target),)
ACTIVE_TARGET := $(shell cat .target)
else
ACTIVE_TARGET := $(DEFAULT_TARGET)
endif

include targets/$(ACTIVE_TARGET).mk

LLVM_BIN ?= /opt/homebrew/opt/llvm/bin
OPT      := $(LLVM_BIN)/opt
SPIRV_T  := llvm-spirv
SPIRV_V  := spirv-val
SPIRV_D  := spirv-dis

BUILD := build/$(ACTIVE_TARGET)

.PHONY: all targets select doctor scan aot aot-all isa-cache perf-gate negative test clean

all: doctor scan aot isa-cache perf-gate

# F5 — SPIR-V ISA-proxy performance report: translated kernel vs
# native-quality baseline, Op-instruction counts (static, non-gating until A1).
perf-gate: translator/ptx2llvm.bin
	@bash test/perf_gate.sh

# Honest-error contract under hostile inputs (translator + scanner).
negative: translator/ptx2llvm.bin scan/arcscan
	@bash test/negative_arc.sh

# F4/A2 — the program-binary ISA cache: compile once through the vendor
# driver, capture the DRIVER-COMPILED binary (CL_PROGRAM_BINARIES), cache,
# reload. Warm launches never compile IR. Honest PENDING when no device.
isa-cache: tools/isa_cache.bin
	@./tools/isa_cache.bin

tools/isa_cache.bin: tools/isa_cache.c
	$(CC) -O2 -std=c11 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework OpenCL -o $@ tools/isa_cache.c

targets:
	@echo "Bare CUDA Arc — target pull-down"
	@echo "================================"
	@for t in $(TARGETS); do \
	  gpu=$$(grep -E '^TARGET_GPU' targets/$$t.mk | cut -d= -f2- | sed 's/^ *//'); \
	  arch=$$(grep -E '^TARGET_ARCH' targets/$$t.mk | cut -d= -f2- | sed 's/^ *//'); \
	  env=$$(grep -E '^TARGET_SPIRV_ENV' targets/$$t.mk | cut -d= -f2- | sed 's/^ *//'); \
	  drv=$$(grep -E '^TARGET_DRIVER' targets/$$t.mk | cut -d= -f2- | sed 's/^ *//' | cut -c1-40); \
	  mark=" "; [ "$$t" = "$(ACTIVE_TARGET)" ] && mark="*"; \
	  printf "%s %-9s %-24s %-24s %-6s %s\n" "$$mark" "$$t" "$$gpu" "$$arch" "$$env" "$$drv"; \
	done
	@echo "active: $(ACTIVE_TARGET)  (override: make TARGET=<name> ... | make select)"

select:
	@bash scripts/select_target.sh

doctor:
	@bash scripts/doctor.sh
	@echo "[doctor] active target: $(ACTIVE_TARGET) — $(TARGET_GPU) ($(TARGET_ARCH), spirv-val --target-env=$(TARGET_SPIRV_ENV))"

scan: scan/arcscan
	@./scan/arcscan fixtures/vectorAdd.real.fatbin

scan/arcscan: scan/arcscan.c
	$(CC) -O2 -std=c11 -Wall -Wextra -Werror -DHAVE_ZSTD -I/opt/homebrew/include -o $@ scan/arcscan.c -lz -L/opt/homebrew/lib -lzstd

aot: translator/ptx2llvm.bin $(BUILD)
	@mkdir -p $(BUILD)
	@./translator/ptx2llvm.bin fixtures/vectorAdd.ptx _Z9vectorAddPKfS0_Pfi > $(BUILD)/vectorAdd.ll
	@$(OPT) -O2 -o $(BUILD)/vectorAdd.opt.ll $(BUILD)/vectorAdd.ll 2>$(BUILD)/opt.log; \
	rc=$$?; grep -v "failed to create target machine" $(BUILD)/opt.log || true; exit $$rc
	@$(SPIRV_T) $(BUILD)/vectorAdd.opt.ll -o $(BUILD)/vectorAdd.spv
	@$(SPIRV_V) --target-env $(TARGET_SPIRV_ENV) $(BUILD)/vectorAdd.spv
	@bash test/validate_spv.sh $(SPIRV_D) $(BUILD)/vectorAdd.spv \
	    "$(TARGET_NAME)" "$(TARGET_GPU)" "$(TARGET_SPIRV_ENV)" "_Z9vectorAddPKfS0_Pfi"

aot-all:
	@for t in $(TARGETS); do echo "== target: $$t =="; $(MAKE) --no-print-directory TARGET=$$t aot || exit 1; done

test: all
	@bash test/run_tests.sh

translator/ptx2llvm.bin: translator/ptx2llvm.c translator/ptx2llvm_main.c
	$(CC) -O2 -std=c11 -Wall -Wextra -Werror -o $@ translator/ptx2llvm.c translator/ptx2llvm_main.c

clean:
	rm -rf build scan/arcscan translator/ptx2llvm.bin

$(BUILD):
	mkdir -p $(BUILD)
