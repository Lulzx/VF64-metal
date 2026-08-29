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

The grammar supports typed `double` parameters, immutable `let` bindings,
decimal literals, parentheses, unary minus, `+`, `-`, `*`, `/`, and the
`sqrt`, `fma`, `remainder`, and `round` functions. It is deliberately
straight-line to match VF64 v1. Comparisons are available as `eq`, `le`, `lt`,
`eq_signaling`, `le_quiet`, and `lt_quiet`; they produce a condition consumed
by `select(condition, when_true, when_false)`. Unsupported syntax and unknown
values are hard diagnostics.

Integer and binary16/binary32 conversion opcodes are part of VF64 v1 but are
not exposed by this double-only source grammar. They require a typed integer
extension rather than pretending raw integer bits are a `double` value.

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
