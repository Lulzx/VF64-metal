# Certified round-to-nearest division

The no-flags `soft_div64` and `vf64_div_rne` entry points use a certified
reciprocal for normal finite operands. RNE means round to nearest, ties to even.
Status-returning and directed-rounding entry points retain the restoring
implementation. Non-normal operands and failed seed or reciprocal certificates
also use that implementation with the original operands, preserving its NaN
payload policy. Overflow and subnormal results use the existing round packer.

The leaf in
[CertifiedDivision.metal](../Sources/VF64Metal/Shaders/IEEE/CertifiedDivision.metal) takes unsigned integers U,V with 1/2 <= U/V < 1,
2^63 <= V < 2^64, and V divisible by 2^11. Let beta=2^32, C=2^63,
b=floor(V/beta), and R=C/b. The caller supplies the binary32 estimate
`fast::divide(1,float(b)*2^-31)*2^32`. The leaf requires 0 <= estimate < 2^33,
selects zero before converting an invalid estimate, and clamps the converted
seed s into [beta/2,beta-1]. These ordered comparisons reject nonfinite seeds.

An integer Newton correction adds or subtracts floor(s*abs(C-bs)/C), using the
high and low halves of its exact product. Its result is at most ceil(R);
one decrement when its product with b reaches C makes that product smaller than
C. The leaf accepts r only when br<C and C-br<2b, exactly 0<R-r<2.
This certificate makes accepted correctness independent of floating seed accuracy.

With rho=r-2, the first quotient digit is h=high32(high32(U)*rho).
The remainder W=(U*2^31-hV)/8 lies in [0,2^64). The second estimate is
q=high32(high32(W)*rho)+4. For Z=U*2^63/V, the proxy z=h*2^32+16q satisfies
-16<z-Z<64. Whenever q modulo 32 is below four, the exact modular residual
for q rounded down to a multiple of eight determines the side of the nearby
512-spaced rounding threshold. That correction is required. Addition, including
its carry, assembles the proxy; jamming seven bits then feeds the existing packer.
Unsigned wrap is intentional for the residual calculations.

Every integer operation is unsigned with defined wrap; invalid reciprocal
candidates are masked before quotient use. Only an accepted proxy reaches the
packer. Consumers must disable fast math and floating-point contraction.

This is established reciprocal division arithmetic, independently adapted from
the public mathematical construction in [CCCL's division implementation](https://github.com/NVIDIA/cccl/blob/b7077689c9ee96fe69f69c6fa2727e96c46ee3a2/libcudacxx/include/cuda/__fp/fpemu_impl_div.h)
(Apache-2.0 WITH LLVM-exception), [SoftFloat's division sequence](https://github.com/ucb-bar/berkeley-softfloat-3/blob/07ebd29db0cfb55723a79fbbffe99103ef38e305/source/f64_div.c)
(BSD-3-Clause), and [Lefèvre and Zimmermann's division analysis](https://www.vinc17.net/research/papers/arith24.pdf).
No implementation text was copied, and no novelty or formal proof of every
binary64 input is claimed. Host checks compared the leaf with exact 128-bit
integer certificates and rounding-grid relations for one million arbitrary
seeds, and with native binary64 division for four million signed normal operand
pairs. On the GPU, `exact-div` in `vf64-metal validate` compares the no-flags
division with native binary64 bit for bit.
