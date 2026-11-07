# Test Results — Bare CUDA Arc v0

**Project:** Bare CUDA Arc (repo `bare-cuda-arc`) · **Date:** 2026-11-07 ·
**All measurements taken this session, live, on the build host.**

**Build host:** Apple M4 Mac mini, macOS 26.6 — LLVM 23.1.5 (`opt`),
SPIRV-LLVM-Translator 23.1.3 (`llvm-spirv`), SPIRV-Tools 1.4.363.0
(`spirv-val` / `spirv-dis`). **No Intel GPU was present** — by design: the
v0 lane is hardware-free; the live gate (`scripts/verify_arc.sh`) arms on
the Arc host.

## 1. Scanner: real nvcc 12.4 fatbin → FULLY PORTABLE v0

Input: `fixtures/vectorAdd.real.fatbin` — the genuine CUDA 12.4 nvcc
fatbin shared across the Bare CUDA family's verified records.

```
fatbin containers: 1 · PTX: 1,034 bytes decoded · kernels: 1
distinct opcodes: 12 · hits: 22
feasibility vs target 'arc-a770': 22/22 hits in v0 profile — FULLY PORTABLE v0
```

Each opcode carries its SPIR-V mapping in the feasibility profile
(`OpGlobalInvocationId`, `OpLoad`/`OpStore` CrossWorkgroup, `OpFAdd`, …).

## 2. Translator + optimizer

- Fixture kernel translated (exit 0); IR passed `opt` module verification.
- `opt -O2` promoted **all** register slots (allocas after optimization: 0).
- Kernel emits as `define spir_kernel void @…` with the `_ntid_x`
  blockDim-as-data argument and `ptr addrspace(1)` global params.

## 3. SPIR-V artifacts: three Arc profiles, Khronos-validated

| Target | GPU | Env | Validation | Size |
|---|---|---|---|---|
| `arc-a770` | Arc A770 16GB (Xe-HPG) | `spv1.5` | Kernel cap + entry + symbol + OpenCL.std + CrossWorkgroup, spirv-val clean | 1,532 B |
| `arc-b580` | Arc B580 12GB (Xe2-HPG) | `spv1.5` | identical structural proof | 1,532 B |
| `flex-170` | Flex 170 (Xe-HPG server) | `spv1.5` | identical structural proof | 1,532 B |

Structural spot-checks: `get_global_id` work-item builtin present,
CrossWorkgroup storage class referenced. Round-trip proof:
`llvm-spirv -r` reverse-translates the binary back to LLVM IR.

## 4. Honesty contract

- Crafted kernel with `shfl.idx.b32` → **exit 2**, opcode named on stderr.
- Unknown kernel name → exit 1.
- Validator negative-tested: rejects a non-SPIR-V file.

## 5. Compression coverage

LZ4 (real fatbin) · zstd · deflate · raw-PTX passthrough — all decoded and
censused (same proven decoder family as the Metal/ROCm siblings).

## 6. Harness record

`make test` → **27/27 green**, builds `-Wall -Wextra -Werror` clean.
`make doctor` → PASS.

## 7. What is NOT verified yet (honest residual)

- **No kernel has executed on Intel hardware yet.** v0's claim ends at
  validated-SPIR-V level. The live gate detects the Arc host
  (intel-compute-runtime + clinfo) and will run the
  `clCreateProgramWithIL`/launch suite as ROADMAP phase 2.
- OpenCL builtins are SPIR 1.2-convention imports (roundtrip-proven);
  OpenCL.std ExtInst mapping is a phase-2 refinement.
- Profiled-not-lowered: `shfl`, `bar.sync`, `atom.add.u32`, `selp` — named
  by the scanner, refused by the translator.

**Reproduce:** `make doctor && make test` (hardware-free), `make aot-all`
(all three profiles), `scripts/verify_arc.sh` (arms on the Arc host).
