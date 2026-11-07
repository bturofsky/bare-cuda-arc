# Bare CUDA Arc (Xe)

**CUDA kernels compiled ahead-of-time to validated SPIR-V — the portable IR
Intel's compute runtime (intel-compute-runtime / Level Zero) consumes on
Arc — no runtime interception, no source rewrite.**

Third sibling in the **Bare CUDA** family:
[Bare CUDA Metal](https://github.com/bturofsky/bare-cuda-metal) (Apple
silicon, bitwise-verified vs RTX 8000) and
[Bare CUDA ROCm](https://github.com/bturofsky/bare-cuda-rocm) (AMD MI210 /
W7800 / W7900 via LLVM AMDGPU). Same discipline again: translate once,
compile **AOT**, validate byte-level, hard-fail loudly on anything
unsupported.

```
+-----------------------------------------------------------------------------------+
|                     CUDA binary (real nvcc 12.4 fatbin)                           |
+-----------------------------------------------------------------------------------+
                                   |
                                   v  [ portability scanner ]
              fatbin container walk -> PTX extract (LZ4 / zstd / deflate)
                                   -> opcode census -> per-target SPIR-V feasibility
                                   |
                                   v  [ translator ]
                 PTX subset -> LLVM IR (spir64-unknown-unknown, OpenCL kernel)
                     spir_kernel, params addrspace(1) = CrossWorkgroup
                     get_global_id / get_group_id builtins, _ntid_x as data
                                   |
                                   v  [ LLVM AOT pipeline ]
                       opt -O2  ->  llvm-spirv
                                   |
                                   v
                    SPIR-V binary (.spv) — Khronos spirv-val clean
                    per target env: spv1.5 profiles for all three GPUs
                                   |
                                   v
        [ hardware gate: clCreateProgramWithIL + launch on the Arc host (phase 2) ]
```

## Verified today (v0, all measured — see [VERIFIED.md](VERIFIED.md))

| Gate | Proves | Result |
|---|---|---|
| Scanner | real nvcc 12.4 fatbin (LZ4-PTX) → census | 22/22 opcode hits — **FULLY PORTABLE v0** |
| Translator | PTX → LLVM IR | IR passes `opt` verification |
| Optimizer | `opt -O2` | register slots fully promoted |
| SPIR-V lane | `llvm-spirv` × 3 target profiles | Kernel capability + `OpEntryPoint Kernel` + kernel symbol + OpenCL.std + CrossWorkgroup, `spirv-val --target-env spv1.5` clean |
| Honesty | unsupported opcode | **exit 2, opcode named** — never a wrong translation |
| Harness | 27 structured checks | **27/27 green**, builds warning-free under `-Wall -Wextra -Werror` |

The entire AOT lane runs on **any machine with LLVM + the SPIR-V
translator — no Intel GPU required**. The live-GPU gate
(`scripts/verify_arc.sh`) auto-arms on the Arc host; nothing is faked in
between.

## Target pull-down

| Target | GPU | Architecture | SPIR-V env | Driver lane |
|---|---|---|---|---|
| `arc-a770` | Intel Arc A770 16GB | Xe-HPG (DG2-512, Alchemist) | `spv1.5` | intel-compute-runtime / Level Zero (OpenCL 3.0) |
| `arc-b580` | Intel Arc B580 12GB | Xe2-HPG (Battlemage) | `spv1.5` | intel-compute-runtime / Level Zero |
| `flex-170` | Intel Flex 170 | Xe-HPG server | `spv1.5` | Level Zero multi-device (phase 3) |

```bash
make targets          # list the pull-down
make select           # interactive picker (persists .target)
make aot              # build + validate for the selected target
make aot-all          # build for every registered target
make test             # the 27-check acceptance harness
make doctor           # toolchain audit
```

Adding a GPU is one `targets/<name>.mk` file.

## Design rules (what makes this "bare")

1. **Translate once, compile AOT.** The SPIR-V binary is a finished,
   validated artifact — the driver's front-end never sees CUDA, and the
   Intel back-end (IGC) compiles it to Xe ISA at load time with the full
   driver-side optimization stack. No runtime bytecode translation of CUDA.
2. **Honesty contract.** An opcode outside the v0 profile hard-fails with
   the opcode *named* (`exit 2`) — structurally unable to emit a wrong
   translation.
3. **blockDim travels as data.** `_ntid_x` rides as an explicit kernel
   argument — the family calling convention, shared with Metal (buffer 30)
   and ROCm.
4. **Validator-gated artifacts.** Every `.spv` must prove Kernel capability,
   Kernel entry point, the kernel symbol, OpenCL.std, CrossWorkgroup
   storage, and pass `spirv-val` at the target's env — or the gate fails.
   The validator itself is negative-tested.

## What runs today vs. what's next

- **Today (v0):** scanner over real nvcc fatbins, PTX→LLVM IR translation of
  the verified vectorAdd-class profile, full LLVM optimization, SPIR-V
  binaries validated per target env, structured acceptance harness.
- **Phase 2 (hardware gate):** `clCreateProgramWithIL` + launch of the
  compiled `.spv` on the A770, element-verified vs CPU truth; EU/subgroup
  census; host-pointer zero-copy. Skeleton already auto-detects the host.
- **Phase 3:** Level Zero multi-device lane (Flex 170 class), subgroup
  shuffles, more of the scanner-ranked census.

See [ARCHITECTURE.md](ARCHITECTURE.md) and [ROADMAP.md](ROADMAP.md).

## Family

| Project | Target | Status |
|---|---|---|
| [Bare CUDA Metal](https://github.com/bturofsky/bare-cuda-metal) | Apple M1–M5 via Metal, AOT `.metallib` | bitwise-verified vs RTX 8000, 15 suites, 22-check gate |
| [Bare CUDA ROCm](https://github.com/bturofsky/bare-cuda-rocm) | AMD MI210 / W7800 / W7900 via LLVM AMDGPU | v0: native AMDGCN code objects, hardware-free AOT lane |
| **Bare CUDA Arc** (this repo) | Intel Arc A770 / B580 / Flex 170 via SPIR-V | v0: validated SPIR-V lane, hardware-free |
| [Bare CUDA Adreno](https://github.com/bturofsky/bare-cuda-adreno) | Qualcomm Adreno 830 / 750 / 740 | v0: SPIR-V lane |

## Credits & license

MIT — original work. NVIDIA, AMD, Intel and Qualcomm own their respective
trademarks; this is an independent interoperability project, unaffiliated
with any of them, shipping none of their SDK code.
