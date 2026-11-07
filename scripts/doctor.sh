#!/usr/bin/env bash
# doctor.sh — Bare CUDA Arc toolchain audit. Exit non-zero if the gate cannot run.
set -uo pipefail
fail=0
say() { printf '%s\n' "$*"; }
ok()  { say "  [ok] $*"; }
bad() { say "  [MISSING] $*"; fail=1; }

say "Bare CUDA Arc — doctor"

command -v llvm-spirv >/dev/null 2>&1 && ok "llvm-spirv: $(command -v llvm-spirv) ($(llvm-spirv --version 2>/dev/null | head -1))" \
  || bad "llvm-spirv not found (brew install spirv-llvm-translator)"
command -v spirv-val >/dev/null 2>&1 && ok "spirv-val: $(command -v spirv-val)" || bad "spirv-val missing (brew install spirv-tools)"
command -v spirv-dis >/dev/null 2>&1 && ok "spirv-dis: $(command -v spirv-dis)" || bad "spirv-dis missing (brew install spirv-tools)"
/opt/homebrew/opt/llvm/bin/opt --version >/dev/null 2>&1 && ok "LLVM opt: /opt/homebrew/opt/llvm/bin/opt" || bad "LLVM opt missing"

[ -s fixtures/vectorAdd.ptx ] && ok "fixture PTX present" || bad "fixtures/vectorAdd.ptx missing"
[ -s fixtures/vectorAdd.real.fatbin ] && ok "real nvcc 12.4 fatbin fixture present" || bad "fixtures/vectorAdd.real.fatbin missing"

echo '#include <zstd.h>' | cc -I/opt/homebrew/include -x c -fsyntax-only - 2>/dev/null \
  && ok "libzstd headers (fatbin zstd payloads)" || bad "libzstd headers missing (brew install zstd)"

CACHE="${CUDA_METAL_AOT_CACHE:-$HOME/.cache/cuda-metal}"
mkdir -p "$CACHE" 2>/dev/null && [ -w "$CACHE" ] \
  && ok "artifact cache dir writable: $CACHE" || bad "cache dir not writable: $CACHE"

if [ "$fail" -eq 0 ]; then
  say "doctor: PASS — the SPIR-V AOT lane can run on this machine (no GPU required)"
else
  say "doctor: FAIL — fix the missing pieces above"
fi
exit "$fail"
