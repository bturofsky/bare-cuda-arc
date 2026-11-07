#!/usr/bin/env bash
# perf_gate.sh — the ISA-proxy performance comparison (family F5, Arc A1-preflight).
#
# Same workload, two SPIR-V modules:
#   baseline — hand-authored native-quality IR (test/perf_baseline.ll)
#   ours     — the translated CUDA kernel (PTX -> our LLVM IR -> llvm-spirv)
# Metric: Op-instruction counts via spirv-dis. STATIC PROXY, honestly
# labeled: the real <= 2.0x-on-GPU-clocks gate fires at A1 on the Arc host.
set -uo pipefail
cd "$(dirname "$0")/.."
LLVM_BIN=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
ENVV=${TARGET_SPIRV_ENV:-spv1.5}
TN=${TARGET_NAME:-arc-a770}
TDIR=build/$TN
mkdir -p "$TDIR"

# ours (the aot pipeline pieces)
./translator/ptx2llvm.bin fixtures/vectorAdd.ptx _Z9vectorAddPKfS0_Pfi > "$TDIR/vectorAdd.ll" 2>/dev/null || exit 1
"$LLVM_BIN/opt" -O2 -o "$TDIR/vectorAdd.opt.ll" "$TDIR/vectorAdd.ll" 2>/dev/null || exit 1
llvm-spirv "$TDIR/vectorAdd.opt.ll" -o "$TDIR/vectorAdd.spv" 2>/dev/null || exit 1

# baseline
"$LLVM_BIN/opt" -O2 -o "$TDIR/baseline.opt.ll" test/perf_baseline.ll 2>/dev/null || exit 1
llvm-spirv "$TDIR/baseline.opt.ll" -o "$TDIR/baseline.spv" 2>/dev/null || exit 1

spirv-val --target-env "$ENVV" "$TDIR/vectorAdd.spv" 2>/dev/null || exit 1
spirv-val --target-env "$ENVV" "$TDIR/baseline.spv" 2>/dev/null || exit 1

count() { spirv-dis "$1" 2>/dev/null | grep -cE '(^|=[[:space:]]+)Op[A-Z]'; }

NB=$(count "$TDIR/baseline.spv"); NO=$(count "$TDIR/vectorAdd.spv")
[ "${NB:-0}" -gt 0 ] && [ "${NO:-0}" -gt 0 ] || { echo "PERF PROXY FAIL: empty disassembly"; exit 1; }
RATIO=$(python3 -c "print(f'{$NO/$NB:.2f}')")

echo "SPIR-V ISA-PROXY REPORT [$TN] (env $ENVV) — static, non-gating"
echo "  native-quality baseline : $NB Op instructions"
echo "  translated CUDA kernel  : $NO Op instructions"
echo "  ratio                   : ${RATIO}x"
echo "  both modules spirv-val clean at $ENVV; the <= 2.0x GPU-clock gate fires at A1 on the Arc host"
exit 0
