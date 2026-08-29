# Pair-resident compiler representation

CuMetal's `lower_to_llvm.cpp` already emits the important arithmetic shape:

- `llvm.fma.f32(a.hi, b.hi, -product)` for the high-product residual;
- both cross products and the `lo * lo` term;
- accurate pair renormalization.

The compiler should make the pair authoritative within an arithmetic region:

```cpp
struct EmulatedF64Register {
    std::string hi;
    std::string lo;
    bool pair_valid;
    std::string bits;
    bool bits_valid;
};
```

After pair arithmetic, retain `hi` and `lo`, invalidate the packed bits, and
feed the pair directly to the next FP64 operation. Materialize IEEE bits only
when an instruction can observe them.

This is an internal compiler representation. Global, shared, local, parameter,
call, and externally visible storage retains the declared 64-bit ABI.

