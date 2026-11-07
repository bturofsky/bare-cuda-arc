# Architecture — Bare CUDA Arc v0

The lowering contract: every transformation between a CUDA binary and a
validated SPIR-V artifact, exactly, with its failure mode.

## 1. Lane boundary

- **Lane A (AOT, hardware-free).** fatbin → PTX → LLVM IR → `opt -O2` →
  `llvm-spirv` → SPIR-V binary, validated by Khronos `spirv-val` at the
  target's env plus structural checks. Runs anywhere with the SPIR-V
  toolchain.
- **Lane B (hardware gate).** `clCreateProgramWithIL` + launch on a real Arc
  host, element-verified vs CPU truth. Auto-detects; refuses to pretend.

## 2. Scanner (`scan/arcscan.c`)

Identical container machinery to the family standard (byte-verified vs
CUDA 12.4 in the Metal project): fatbin walk, LZ4/zstd/deflate decode,
cuobjdump-dump fallback, opcode census. The feasibility profile is
re-expressed in SPIR-V terms — the census verdict (`FULLY PORTABLE v0`,
22/22) maps each opcode to its SPIR-V lowering.

## 3. Translator (`translator/ptx2llvm.c`)

PTX subset → textual LLVM IR, `target triple = "spir64-unknown-unknown"`.

### Register model

Every PTX virtual register gets an entry-block alloca slot (SPIR-V Function
storage after translation), typed by PTX class:

| PTX class | LLVM slot |
|---|---|
| `%rdN` (.b64/.u64/.s64) | `alloca i64` |
| `%rN` (.b32/.u32/.s32) | `alloca i32` |
| `%fN` (.f32) | `alloca float` |
| `%pN` (.pred) | `alloca i1` |

No phi nodes needed for arbitrary control flow; `opt -O2` (mem2reg) promotes
the slots before translation. Every intermediate value is an SSA temp
referenced by integer id — no name aliasing.

### Lowering contract

| PTX | LLVM IR / SPIR-V |
|---|---|
| kernel pointer params | `ptr addrspace(1)` → CrossWorkgroup |
| `ld.param.u64 %rd, [p]` | `ptrtoint ptr addrspace(1) %p to i64` → slot |
| `mov.u32 %r, %tid.x` | `call spir_func i32 @_Z13get_global_idj(i32 0)` |
| `mov.u32 %r, %ctaid.x` | `call spir_func i32 @_Z12get_group_idj(i32 0)` |
| `mov.u32 %r, %ntid.x` | implicit trailing kernel argument `_ntid_x` (family calling convention) |
| `mad.lo.s32` | exact `OpIMul i32` + `OpIAdd i32` |
| `mul.wide.s32 %rd, r, k` | `sext` → `OpIMul i64` |
| `setp.<cc>.s32` | `icmp` → `OpSGreaterThanEqual` etc. |
| `ld/st.global.f32` | `inttoptr` → CrossWorkgroup `OpLoad`/`OpStore` |
| `add.f32` | `OpFAdd` |
| `cvta.to.global.u64` | identity — addrspace(1) *is* the global space |
| `bra` / `@p bra` | `OpBranch` / `OpBranchConditional` + fallthrough block |
| `ret` | `OpReturn` / `OpFunctionEnd` |
| kernel definition | `define spir_kernel void @<name>(...)` → `OpEntryPoint Kernel` |

**Builtin imports:** the OpenCL builtins (`get_global_id`,
`get_group_id`) are emitted as SPIR 1.2-convention imported-linkage
functions — the form intel-compute-runtime resolves natively and the
official translator round-trips (`llvm-spirv -r` proven in the gate).

### Honesty contract

Any opcode outside the supported set aborts with the opcode NAMED and exit
2. The pipeline structurally cannot emit a wrong translation.

## 4. Validation (`test/validate_spv.sh`)

Every `.spv` must, via Khronos tooling:

1. pass `spirv-val --target-env <target env>` (per-target: `spv1.5`)
2. show `OpCapability Kernel` and `OpEntryPoint Kernel`
3. contain the kernel symbol string
4. import `OpenCL.std`
5. reference `CrossWorkgroup` storage

The validator is negative-tested (must reject junk).

## 5. Known v0 limits (honest)

- Lane B pending until the Arc host exists; absence is reported, not
  simulated.
- `opt` prints a benign warning ("failed to create target machine" for
  spir64 — no LLVM target needed for target-independent IR optimization);
  the Makefile filters exactly that line and preserves opt's exit code.
- Profiled-not-lowered opcodes (`shfl`, `bar.sync`, `atom.add.u32`, `selp`)
  are counted and named by the scanner; the translator refuses them.
- fp64 on Arc consumer parts is driver-emulated — kernels relying on
  native fp64 rate should target the Flex lane; recorded per target.
