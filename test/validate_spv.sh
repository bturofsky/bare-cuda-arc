#!/usr/bin/env bash
# validate_spv.sh — structural proof that a .spv is a genuine OpenCL-kernel
# SPIR-V module for the requested profile. Exits non-zero on any mismatch.
#   usage: validate_spv.sh <spirv-dis> <file.spv> <target_name> <gpu> <spv_env> <kernel_name>
set -euo pipefail

DIS="$1"; SPV="$2"; TNAME="$3"; GPU="$4"; ENVV="$5"; KERNEL="$6"

[ -s "$SPV" ] || { echo "VALIDATE FAIL: $SPV missing/empty"; exit 1; }

spirv-val --target-env "$ENVV" "$SPV" 2>/dev/null \
  || { echo "VALIDATE FAIL: spirv-val --target-env $ENVV rejected the module"; exit 1; }

ASM=$("$DIS" "$SPV" 2>/dev/null)

echo "$ASM" | grep -q "OpCapability Kernel" || { echo "VALIDATE FAIL: no Kernel capability"; exit 1; }
echo "$ASM" | grep -q "OpEntryPoint Kernel" || { echo "VALIDATE FAIL: no Kernel entry point"; exit 1; }
echo "$ASM" | grep -q "\"$KERNEL\"" || { echo "VALIDATE FAIL: kernel symbol missing"; exit 1; }
echo "$ASM" | grep -q "OpenCL.std" || { echo "VALIDATE FAIL: no OpenCL.std import"; exit 1; }
echo "$ASM" | grep -q "CrossWorkgroup" || { echo "VALIDATE FAIL: no CrossWorkgroup storage"; exit 1; }

BYTES=$(wc -c < "$SPV" | tr -d ' ')
echo "VALIDATE OK [$TNAME] $GPU (spirv-val --target-env=$ENVV): Kernel capability + entry \"$KERNEL\" + OpenCL.std + CrossWorkgroup, $BYTES bytes"
