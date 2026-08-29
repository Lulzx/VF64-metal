; Direct AIR calls are intentional: source-language backends link this module
; with vf64-support.air and do not use Metal visible-function tables.
target triple = "air64_v28-apple-macosx26.0.0"

declare i64 @vf64_add_rne(i64, i64)
declare i64 @vf64_mul_rne(i64, i64)
declare i64 @vf64_div_rne(i64, i64)
declare i64 @vf64_sqrt_rne(i64)
declare i64 @vf64_fma_rne(i64, i64, i64)
declare i1 @vf64_lt(i64, i64)
declare i64 @vf64_ui64_to_f64(i64, i32)

define void @vf64_support_probe(float addrspace(1)* %output) #0 {
entry:
  %out = bitcast float addrspace(1)* %output to i64 addrspace(1)*
  %r0 = call i64 @vf64_add_rne(i64 4607182418800017408, i64 4363988038922010624)
  %r1 = call i64 @vf64_mul_rne(i64 4607182418800017409, i64 4613937818241073152)
  %r2 = call i64 @vf64_div_rne(i64 4607182418800017408, i64 4613937818241073152)
  %r3 = call i64 @vf64_sqrt_rne(i64 4611686018427387904)
  %r4 = call i64 @vf64_fma_rne(i64 4607182418800017409, i64 4607182418800017409, i64 -4616189618054758398)
  %r5i1 = call i1 @vf64_lt(i64 -4616189618054758400, i64 0)
  %r5 = zext i1 %r5i1 to i64
  %r6 = call i64 @vf64_ui64_to_f64(i64 -1, i32 0)
  store i64 %r0, i64 addrspace(1)* %out, align 8
  %p1 = getelementptr i64, i64 addrspace(1)* %out, i64 1
  store i64 %r1, i64 addrspace(1)* %p1, align 8
  %p2 = getelementptr i64, i64 addrspace(1)* %out, i64 2
  store i64 %r2, i64 addrspace(1)* %p2, align 8
  %p3 = getelementptr i64, i64 addrspace(1)* %out, i64 3
  store i64 %r3, i64 addrspace(1)* %p3, align 8
  %p4 = getelementptr i64, i64 addrspace(1)* %out, i64 4
  store i64 %r4, i64 addrspace(1)* %p4, align 8
  %p5 = getelementptr i64, i64 addrspace(1)* %out, i64 5
  store i64 %r5, i64 addrspace(1)* %p5, align 8
  %p6 = getelementptr i64, i64 addrspace(1)* %out, i64 6
  store i64 %r6, i64 addrspace(1)* %p6, align 8
  ret void
}

attributes #0 = { "air.kernel" "air.version"="2.8" }

!air.kernel = !{!0}
!0 = !{void (float addrspace(1)*)* @vf64_support_probe, !1, !2}
!1 = !{}
!2 = !{!3}
!3 = !{i32 0, !"air.buffer", !"air.location_index", i32 0, i32 1, !"air.read_write", !"air.address_space", i32 1, !"air.arg_type_size", i32 4, !"air.arg_type_align_size", i32 4, !"air.arg_type_name", !"float", !"air.arg_name", !"output"}
!air.compile_options = !{!4, !5, !6}
!4 = !{!"air.compile.denorms_disable"}
!5 = !{!"air.compile.fast_math_enable"}
!6 = !{!"air.compile.framebuffer_fetch_enable"}
!air.version = !{!7}
!air.language_version = !{!8}
!7 = !{i32 2, i32 8, i32 0}
!8 = !{!"Metal", i32 4, i32 0, i32 0}
