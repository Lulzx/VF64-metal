# Certified round-to-nearest division

The no-flags `soft_div64` and `vf64_div_rne` entry points use a certified
reciprocal for normal finite operands. RNE means round to nearest, ties to even.
Status-returning and directed-rounding entry points retain the restoring
implementation. Non-normal operands and failed reciprocal certificates
also use that implementation with the original operands, preserving its NaN
payload policy. Overflow and subnormal results use the existing round packer.

The arithmetic leaf takes unsigned integers U,V with 1/2 <= U/V < 1,
2^63 <= V < 2^64, and V divisible by 2^11. Let beta=2^32, C=2^63,
b=floor(V/beta), and R=C/b. The caller selects two 16-bit coefficients
from Berkeley SoftFloat's sixteen-entry reciprocal tables using bits 48–51 of
the binary64 divisor. The integer interpolation and correction give
an unsigned 32-bit seed s. SoftFloat's documented contract is lower-sided with
0 <= R-s <= 2.006; this is a cited implementation bound, not a new derivation
of its constants.

Let P=bs. Reject P>=C before testing the unsigned gap. If C-P>=2b, increment s
once and update P by adding b. This branch has R-s in [2,2.006], so the
increment leaves an error in [1,1.006] and cannot overflow. The other branch
already has error strictly between zero and two. In both cases the leaf still
checks br<C and C-br<2b, exactly 0<R-r<2. A failed check falls back using the
original binary64 operands. This exact certificate makes accepted arithmetic
independent of the selected coefficients, including corrupted coefficients.

With rho=r-2, the first quotient digit is h=high32(high32(U)*rho).
The remainder W=(U*2^31-hV)/8 lies in [0,2^64). The second estimate is
q=high32(high32(W)*rho)+4. For Z=U*2^63/V, the proxy z=h*2^32+16q satisfies
-16<z-Z<64. Whenever q modulo 32 is below four, the exact modular residual
for q rounded down to a multiple of eight determines the side of the nearby
512-spaced rounding threshold. That correction is required. Addition, including
its carry, assembles the proxy; jamming seven bits then feeds the existing packer.
Unsigned wrap is intentional for the residual calculations.

All intermediate arithmetic is unsigned with defined wrap. Invalid reciprocal
candidates are masked before quotient use; only an accepted proxy reaches the
packer. The support build disables fast math and floating-point contraction.
The tables and seed interpolation below carry their original BSD notice.

This is established reciprocal division arithmetic, independently adapted from
the public mathematical construction in [CCCL's division implementation](https://github.com/NVIDIA/cccl/blob/b7077689c9ee96fe69f69c6fa2727e96c46ee3a2/libcudacxx/include/cuda/__fp/fpemu_impl_div.h)
(Apache-2.0 WITH LLVM-exception), [SoftFloat's division sequence](https://github.com/ucb-bar/berkeley-softfloat-3/blob/07ebd29db0cfb55723a79fbbffe99103ef38e305/source/f64_div.c)
(BSD-3-Clause), and [Lefèvre and Zimmermann's division analysis](https://www.vinc17.net/research/papers/arith24.pdf).
The reciprocal constants and seed formula are adapted from the primary
[SoftFloat reciprocal source](https://github.com/ucb-bar/berkeley-softfloat-3/blob/07ebd29db0cfb55723a79fbbffe99103ef38e305/source/s_approxRecip32_1.c)
and [tables](https://github.com/ucb-bar/berkeley-softfloat-3/blob/07ebd29db0cfb55723a79fbbffe99103ef38e305/source/s_approxRecip_1Ks.c),
under the retained [BSD-3-Clause notice](softfloat-license.txt). Binary
redistributions must reproduce that notice. The quotient pipeline remains an
independent adaptation of the published mathematics. No novelty or formal proof
of every binary64 input is claimed. Independent native tests check exact integer certificates,
rounding-grid relations and native CPU results; device conformance remains a
separate verification obligation.
