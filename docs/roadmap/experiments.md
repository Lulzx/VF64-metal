# Experiment roadmap

These experiments support the canonical [M1–M8 milestone
sequence](../milestones/README.md); they do not replace its exit criteria.

## P0: reproducible evidence

- Store machine-readable results with source hash, OS/Metal version, device,
  command line, corpus seed, warm-up policy, samples, and timestamp source.
- Generate `results/summary.md`; derive public claims from it.
- Add Berkeley TestFloat matrices for every completed `ieee64` operation.

## P1: compiler residency

- Count split/pack/materialization sequences in emitted CuMetal IR.
- Keep pairs resident through straight-line FP64 SSA chains.
- Measure registers, occupancy, spills, chain runtime, and solver behavior.
- Prove every observable boundary retains the current bits and warning.

Acceptance: identical stored results, fewer codecs, and a measured kernel gain
without numerical regression.

## P2: specify `wide48`

- Instrument exponent spans in CG, GMRES, cuPDLP, stencil, GEMV, and SpMV.
- Compare scaled pairs, a shared exponent, and wider-exponent pair encodings.
- Specify overflow, underflow, special values, conversions, and storage first.

Acceptance: one real workload where `fast48` fails or stalls, `wide48` converges
like CPU FP64, and `wide48` materially outperforms `ieee64`.

## P3: probe Apple's matrix substrate

- Benchmark supported INT8, INT4, FP16, BF16, and FP32 matrix paths.
- Differentially determine accumulation and saturation semantics.
- Measure register versus threadgroup placement for multiple planes.

Acceptance: verified semantics and enough measured throughput to pay all
compute, memory, and reconstruction overhead.

## P4: adaptive policy

- Implement GPU-resident exponent-span classification.
- Route tiles/rows to pair, wide, or exact paths.
- Report policy cost, fallback rate, load balance, and adversarial behavior.

Acceptance: overhead remains within a declared budget with no silent downgrade.

## P5: Ozaki/CRT prototype

Only begin after P3 passes:

- implement scaling, residues, Garner reconstruction, and rescaling;
- prove the modulus-product bound for each parameter set;
- test adversarial spans, conditioning, and BLAS grading cases;
- measure bytes and spills instead of assuming `beta = 1`;
- compare against the best pair-FMA backend.

Acceptance: an Apple-GPU win on an end-to-end workload with an independently
stated accuracy/range contract.

## P6: application evidence

Compare FP32, `fast48`, `wide48`, `ieee64`, and CPU FP64 using:

- CG and GMRES residual histories;
- cuPDLP/HiGHS objective, infeasibility, iterations, and time;
- long-timestep stencil stability;
- regular and adversarial sparse matrices;
- dense and batched GEMV/GEMM controls.

Report time to solution and energy where measurable, not only arithmetic rate.
