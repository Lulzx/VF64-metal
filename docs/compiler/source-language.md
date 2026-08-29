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
straight-line to match VF64 v1. Unsupported syntax and unknown values are hard
diagnostics.

This frontend is not presented as CUDA compatibility. The M5 exit still
requires CuMetal to lower its source/PTX `double` path into VF64 and to prove
CUDA-visible materialization boundaries.
