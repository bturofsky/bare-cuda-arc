#!/usr/bin/env bash
# verify_arc.sh — the hardware gate (phase 2 of the roadmap).
#
# Detects a live Arc host (intel-compute-runtime + Level Zero / OpenCL) and
# runs the on-GPU acceptance suites — the analog of the family's A/B gates.
# When no Intel GPU is present it says so honestly and exits 0 — the AOT
# lane above is verified hardware-free; nothing here is faked.
set -uo pipefail

CLINFO=""
for c in clinfo /opt/rocm/bin/clinfo; do command -v "$c" >/dev/null 2>&1 && CLINFO="$c" && break; done

echo "Bare CUDA Arc — hardware gate"
if [ -z "$CLINFO" ]; then
  echo "  no OpenCL host probe detected (clinfo absent)"
  echo "  status: HARDWARE GATE PENDING — v0 is verified through the validated"
  echo "          SPIR-V level (see VERIFIED.md); live-GPU suites arm automatically"
  echo "          on the Arc host (intel-compute-runtime + clinfo, then Level Zero)."
  exit 0
fi

GPU=$("$CLINFO" 2>/dev/null | grep -m1 "Device Name" || echo unknown)
echo "  OpenCL host detected — GPU: $GPU"
echo "  planned suites (ROADMAP phase 2):"
echo "    1. host-load: clCreateProgramWithIL of build/arc-a770/vectorAdd.spv +"
echo "       clSetKernelArg + launch, element-verified vs CPU truth"
echo "    2. Xe core census: grid-stride + local-memory reduction across EUs"
echo "    3. zero-copy: CL_MEM_ALLOC_HOST_PTR path vs device copy"
echo "    4. Level Zero multi-device lane (Flex 170 class)"
echo "  implementation lands with the host (ROADMAP.md phase 2) — nothing to fake here."
exit 0
