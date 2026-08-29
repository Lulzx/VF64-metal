# VF64 source compiler

The `vf64-compile` frontend lowers a small, deterministic numerical kernel
language into VF64 bytecode. It exists as the source-level integration and
conformance surface while the same ISA is integrated into CuMetal's PTX path.

```text
kernel axpy(double alpha, double x, double y) -> double {
    let product: double = alpha * x;
    return product + y;
}
```

Compile one vector program with an explicit numerical policy:

```bash
.build/release/f64-metal vf64-compile --fp64=fast48 --lanes=1024 \
    examples/axpy.vf64 axpy.vf64.bin
```

`wide48` and `ieee64` are accepted in the same flag. Parameters become
slot-major input vectors, the return value becomes output slot zero, and all
source `double` arithmetic becomes mode-tagged VF64 instructions. Users never
call an emulation routine.

The grammar supports `double`, `bool`, `uint32`, `uint64`, `int32`, `int64`,
`float`, and `half` parameters and return values, immutable `let` bindings,
decimal `double` literals, parentheses, unary minus, `+`, `-`, `*`, `/`, and the
`sqrt`, `fma`, `remainder`, and `round` functions. It is deliberately
straight-line to match VF64 v1. Comparisons are available as `eq`, `le`, `lt`,
`eq_signaling`, `le_quiet`, and `lt_quiet`; they produce a condition consumed
by `select(condition, when_true, when_false)`. Unsupported syntax and unknown
values are hard diagnostics. Arithmetic operands must be `double`; comparisons
return `bool`; `select` requires equal branch types.

All VF64 v1 conversion directions are exposed with explicit names:
`uint32_to_double`, `uint64_to_double`, `int32_to_double`,
`int64_to_double`, `double_to_uint32`, `double_to_uint64`,
`double_to_int32`, `double_to_int64`, `double_to_float`, `double_to_half`,
`float_to_double`, and `half_to_double`. Integer, float, and half values retain
the VF64 raw-slot ABI described by the ISA; the source type checker prevents
using those encodings as `double` arithmetic operands.

The compiler creates virtual SSA-like values and performs last-use allocation
to the 32 physical VF64 registers after lowering. Dead operands may share their
slot with an instruction result. A committed 96-operation dependency-chain
regression uses two physical registers, so source length alone does not exhaust
the ISA register file; kernels with more than 32 simultaneously live values
remain a hard diagnostic.

This frontend is not presented as CUDA compatibility. The M5 exit still
requires CuMetal to lower its source/PTX `double` path into VF64 and to prove
CUDA-visible materialization boundaries.

## Automatic precision

Create a measured exponent profile from slot-major packed inputs, then compile
with a declared accumulated accuracy floor:

```bash
.build/release/f64-metal vf64-profile --slots=3 --lanes=1024 \
    input.bin profile.json
.build/release/f64-metal vf64-compile --fp64=auto --lanes=1024 \
    --accuracy-bits=40 --profile=profile.json \
    --diagnostics=selection.json examples/axpy.vf64 axpy-auto.bin
```

The selector chooses per arithmetic instruction. It uses `fast48` only with
finite proof and exponent headroom, `wide48` when scaling is required, and
`ieee64` when proof is missing or the accuracy budget is exhausted. The
diagnostics file records the inferred range, estimated accumulated accuracy,
selected mode, and reason for every decision.
