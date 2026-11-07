; perf_baseline.ll — the NATIVE-quality baseline for the Arc ISA-proxy gate.
; Hand-authored OpenCL-kernel LLVM IR (spir64): exactly what a hand-written
; OpenCL kernel lowers to — direct get_global_id builtins, typed GEP
; addressing, no PTX register model. Compared against our translated kernel
; at the SPIR-V level (Op-instruction counts). STATIC PROXY ONLY: latency
; claims wait for the hardware gate (A1).
target triple = "spir64-unknown-unknown"

declare spir_func i32 @_Z13get_global_idj(i32)
declare spir_func i32 @_Z12get_group_idj(i32)

define spir_kernel void @vectorAdd_native(
    ptr addrspace(1) %a, ptr addrspace(1) %b, ptr addrspace(1) %c,
    i32 %n, i32 %_ntid_x) {
entry:
  %tid = call spir_func i32 @_Z13get_global_idj(i32 0)
  %cond = icmp ult i32 %tid, %n
  br i1 %cond, label %body, label %end
body:
  %ia64 = sext i32 %tid to i64
  %ae = getelementptr float, ptr addrspace(1) %a, i64 %ia64
  %be = getelementptr float, ptr addrspace(1) %b, i64 %ia64
  %av = load float, ptr addrspace(1) %ae
  %bv = load float, ptr addrspace(1) %be
  %s = fadd float %av, %bv
  %ce = getelementptr float, ptr addrspace(1) %c, i64 %ia64
  store float %s, ptr addrspace(1) %ce
  br label %end
end:
  ret void
}
