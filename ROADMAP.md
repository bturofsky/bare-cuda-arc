# Roadmap — Bare CUDA Arc

Each phase ships with a green structured gate (`make test`) and updates
VERIFIED.md with live measurements.

## Phase 1 (shipped, v0): the hardware-free SPIR-V lane

- [x] Portability scanner over real nvcc 12.4 fatbins with SPIR-V feasibility
      profiles — verdict FULLY PORTABLE v0 on the family fixture
- [x] PTX → LLVM IR translator (spir64, OpenCL kernel conventions), honesty
      hard-fails
- [x] Full LLVM optimization + `llvm-spirv` to validated SPIR-V binaries for
      three Arc profiles (A770 / B580 / Flex 170)
- [x] Khronos validator gate (spirv-val per target env + structural checks),
      negative-tested
- [x] Target pull-down, `make doctor`, 27-check harness, `-Werror` builds

## Phase 2 (next): the hardware gate on the Arc host

Trigger: a Linux host with intel-compute-runtime + clinfo + Level Zero.

- [x] **program-binary ISA cache (shipped — family F4/A2):**
      `tools/isa_cache.c` compiles the fixture kernel through the vendor
      driver, captures the DRIVER-COMPILED binary via
      `CL_PROGRAM_BINARIES`, caches it, and reload-verifies with
      `clCreateProgramWithBinary` — warm launches never compile IR (the
      sanctioned thin path; proven live, honest PENDING without a device)
- [ ] host-load: `clCreateProgramWithIL(build/arc-a770/vectorAdd.spv)` +
      launch, element-verified vs CPU truth (the v1 acceptance suite)
- [ ] Xe core census: grid-stride + local-memory reduction across EUs
- [ ] zero-copy: `CL_MEM_ALLOC_HOST_PTR` path vs device copy, timed on GPU
      clocks (the family measurement discipline)
- [ ] Battlemage cross-check: same suites on the B580 profile

## Phase 3: the deeper census (scanner-ordered)

- [ ] subgroup shuffles: `shfl.*` → `OpGroupNonUniformShuffle*`
- [ ] barriers + shared memory: `bar.sync`/`ld.local` → `OpControlBarrier` +
      Workgroup storage
- [ ] atomics: `atom.add.u32` → `OpAtomicIAdd`
- [ ] multi-kernel modules + typed parameter binding (the Metal sibling's
      v2.3 pattern)
- [ ] Level Zero multi-device lane (Flex 170 class)

## Phase 4: the family bridge

Shared acceptance harness across Bare CUDA Metal / ROCm / Arc / Adreno —
one CUDA workload spec, four native backends, one verification record.
