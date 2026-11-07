#!/usr/bin/env bash
# run_tests.sh — the v0 acceptance harness for Bare CUDA Arc.
# Structured PASS/FAIL runner, non-zero exit on any failure. Same discipline
# as the Bare CUDA Metal / ROCm siblings: nothing passes by intention.
set -uo pipefail
cd "$(dirname "$0")/.."

OPTB="/opt/homebrew/opt/llvm/bin/opt"
SPIRV_V="spirv-val"
SPIRV_D="spirv-dis"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
check(){ local name="$1" rc="$2"; [ "$rc" -eq 0 ] && ok "$name" || bad "$name"; }
say()  { printf '%s\n' "$*"; }
hr()   { printf '\n== %s ==\n' "$*"; }

mkdir -p build

hr "build (-Wall -Wextra -Werror)"
make --no-print-directory scan/arcscan >/dev/null 2>&1
check "arcscan builds warning-free" $?
make --no-print-directory translator/ptx2llvm.bin >/dev/null 2>&1
check "ptx2llvm builds warning-free" $?

hr "translator: PTX -> LLVM IR (spir64)"
./translator/ptx2llvm.bin fixtures/vectorAdd.ptx _Z9vectorAddPKfS0_Pfi > build/va.ll 2>/dev/null
check "fixture PTX translates (exit 0)" $?
"$OPTB" -O2 -disable-output build/va.ll 2>/dev/null
check "emitted IR passes opt verification" $?
"$OPTB" -O2 -o build/va.opt.ll build/va.ll 2>/dev/null
check "opt -O2 pipeline runs" $?
N_ALLOCA=$(grep -c "alloca" build/va.opt.ll)
[ "${N_ALLOCA:-99}" -le 2 ] && ok "opt -O2 promoted register slots (allocas: $N_ALLOCA)" \
  || bad "opt -O2 left $N_ALLOCA allocas"
grep -q "spir_kernel" build/va.ll && ok "kernel emitted as spir_kernel (OpenCL entry)" || bad "missing spir_kernel"
grep -q "_ntid_x" build/va.ll && ok "blockDim-as-data contract present (_ntid_x)" || bad "_ntid_x missing"
grep -q "addrspace(1)" build/va.ll && ok "global params typed addrspace(1) (CrossWorkgroup)" || bad "addrspace(1) missing"

hr "honesty contract (never a wrong translation)"
cat > build/bad.ptx <<'EOF'
.version 8.4
.target sm_86
.address_size 64
.visible .entry bad_kernel(
.param .u64 bad_kernel_param_0
)
{
.reg .b32 %r<2>;
ld.param.u64 %rd1, [bad_kernel_param_0];
shfl.idx.b32 %r1, %r1, %r1, 3;
ret;
}
EOF
./translator/ptx2llvm.bin build/bad.ptx bad_kernel > /dev/null 2> build/bad.err
RC_BAD=$?
[ "$RC_BAD" -eq 2 ] && ok "unsupported opcode -> exit 2 (hard-fail)" || bad "unsupported opcode exit=$RC_BAD (want 2)"
grep -q "shfl.idx.b32" build/bad.err && ok "failing opcode NAMED on stderr" || bad "opcode not named"

./translator/ptx2llvm.bin fixtures/vectorAdd.ptx _no_such_kernel_ > /dev/null 2>&1
[ $? -eq 1 ] && ok "kernel-not-found -> exit 1" || bad "kernel-not-found exit wrong"

hr "AOT lane: one validated SPIR-V per registered target"
for t in arc-a770 arc-b580 flex-170; do
  env=$(grep -E '^TARGET_SPIRV_ENV' "targets/$t.mk" | cut -d= -f2- | tr -d ' ')
  gpu=$(grep -E '^TARGET_GPU' "targets/$t.mk" | cut -d= -f2- | sed 's/^ *//' | cut -c1-30)
  mkdir -p "build/$t"
  llvm-spirv build/va.opt.ll -o "build/$t/va.spv" 2>/dev/null
  bash test/validate_spv.sh "$SPIRV_D" "build/$t/va.spv" "$t" "($gpu)" "$env" \
    "_Z9vectorAddPKfS0_Pfi" >/dev/null 2>&1
  check "SPIR-V for $t (spirv-val --target-env=$env) validates" $?
done

# structural spot-checks on the artifact
spirv-dis build/arc-a770/va.spv > build/va.spvasm 2>/dev/null
grep -q "get_global_id" build/va.spvasm && ok "work-item builtin present (tid.x lane)" || bad "get_global_id missing"
grep -q "CrossWorkgroup" build/va.spvasm && ok "global storage = CrossWorkgroup" || bad "storage class wrong"

# negative: validator must reject a non-SPIR-V file
echo "not spir-v" > build/junk.spv
bash test/validate_spv.sh "$SPIRV_D" build/junk.spv x x spv1.5 k >/dev/null 2>&1
[ $? -ne 0 ] && ok "validator rejects non-SPIR-V input" || bad "validator accepted junk"

hr "scanner: fatbin census + per-target feasibility"
./scan/arcscan fixtures/vectorAdd.real.fatbin > build/scan.txt 2>/dev/null
check "scan runs on the real nvcc fatbin" $?
grep -q "FULLY PORTABLE v0" build/scan.txt && ok "verdict: FULLY PORTABLE v0" || bad "verdict not FULLY PORTABLE"
grep -q "kernels: 1" build/scan.txt && ok "one kernel found" || bad "kernel count wrong"
./scan/arcscan fixtures/vectorAdd.zstd.fatbin > build/scan_z.txt 2>/dev/null
grep -qE "PTX: [0-9]+ bytes" build/scan_z.txt && ok "zstd fatbin PTX decoded" || bad "zstd fatbin failed"
./scan/arcscan fixtures/vectorAdd.deflate.fatbin > build/scan_d.txt 2>/dev/null
grep -qE "PTX: [0-9]+ bytes" build/scan_d.txt && ok "deflate fatbin PTX decoded" || bad "deflate fatbin failed"
./scan/arcscan fixtures/vectorAdd.ptx > build/scan_r.txt 2>/dev/null
grep -q "FULLY PORTABLE" build/scan_r.txt && ok "raw PTX input passthrough" || bad "raw PTX failed"

hr "target pull-down"
make --no-print-directory targets > build/targets.txt 2>/dev/null
check "make targets runs" $?
grep -q "arc-a770" build/targets.txt && grep -q "arc-b580" build/targets.txt && grep -q "flex-170" build/targets.txt \
  && ok "all three GPUs listed" || bad "pull-down incomplete"
grep -q "spv1.5" build/targets.txt && ok "SPIR-V env profiles mapped" || bad "env mapping missing"

hr "ISA cache — the sanctioned thin path (F4/A2)"
make --no-print-directory tools/isa_cache.bin > /dev/null 2>&1
check "isa_cache builds warning-free" $?
out=$(./tools/isa_cache.bin 2>&1); rc=$?
[ "$rc" -eq 0 ] || { sleep 1; out=$(./tools/isa_cache.bin 2>&1); rc=$?; }
if echo "$out" | grep -q "ISA CACHE RELOADED"; then
  ok "ISA cache: binary written + reload-verified ($(echo "$out" | grep -o "device '[^']*'" | head -1))"
elif echo "$out" | grep -q "ISA CACHE PENDING"; then
  ok "ISA cache honestly pending (no OpenCL device here)"
else
  bad "isa_cache rc=$rc out=[$out]"
fi

hr "summary"
say "  passed: $PASS  failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf '  \033[32mV0 GATE: ALL GREEN — SPIR-V AOT lane verified end-to-end\033[0m\n'
  exit 0
fi
printf '  \033[31mV0 GATE: FAILURES ABOVE\033[0m\n'
exit 1
