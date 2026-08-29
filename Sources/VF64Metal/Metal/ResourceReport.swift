import Foundation
import Metal

private struct VF64PipelineResources: Codable {
    let kernel: String
    let mode: String
    let operation: String
    let threadExecutionWidth: Int
    let maxTotalThreadsPerThreadgroup: Int
    let staticThreadgroupMemoryBytes: Int
    let benchmarkThreadgroupWidth: Int
}

private struct VF64ResourceAvailability: Codable {
    let physicalRegistersPerThread: String
    let spillBytes: String
    let residentOccupancy: String
    let explanation: String
}

private struct VF64MetalResourceReport: Codable {
    let schema: String
    let device: String
    let registryID: UInt64
    let counterSets: [String]
    let pipelines: [VF64PipelineResources]
    let availability: VF64ResourceAvailability
}

func runMetalResourceReport(_ harness: MetalHarness, json: Bool) throws {
    let kernels = [
        ("pair_add_chain_kernel", "fast48", "add"),
        ("pair_mul_chain_kernel", "fast48", "multiply"),
        ("wide_mul_chain_kernel", "wide48", "multiply"),
        ("soft_add_chain_kernel", "ieee64", "add"),
        ("soft_mul_chain_kernel", "ieee64", "multiply"),
        ("dot_partial_kernel", "fast48", "reduction"),
        ("gemm_fast48_kernel", "fast48", "gemm"),
        ("gemm_wide48_kernel", "wide48", "gemm"),
        ("gemm_ieee64_kernel", "ieee64", "gemm"),
    ]

    let pipelines = try kernels.map { name, mode, operation in
        let state = try harness.pipeline(name)
        return VF64PipelineResources(
            kernel: name,
            mode: mode,
            operation: operation,
            threadExecutionWidth: state.threadExecutionWidth,
            maxTotalThreadsPerThreadgroup: state.maxTotalThreadsPerThreadgroup,
            staticThreadgroupMemoryBytes: state.staticThreadgroupMemoryLength,
            benchmarkThreadgroupWidth: min(
                state.maxTotalThreadsPerThreadgroup,
                max(1, state.threadExecutionWidth * 4)
            )
        )
    }

    let report = VF64MetalResourceReport(
        schema: "vf64.m3.metal-resource-report.v1",
        device: harness.device.name,
        registryID: harness.device.registryID,
        counterSets: (harness.device.counterSets ?? []).map(\.name).sorted(),
        pipelines: pipelines,
        availability: VF64ResourceAvailability(
            physicalRegistersPerThread: "not_exposed",
            spillBytes: "not_exposed",
            residentOccupancy: "not_exposed",
            explanation: "Public Metal pipeline reflection reports SIMD width, maximum threads per threadgroup, and static threadgroup memory; this device exposes only the timestamp counter set. These values are not physical-register, spill, or resident-occupancy measurements."
        )
    )

    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
        return
    }

    print("device=\(report.device) registry_id=\(report.registryID)")
    print("counter_sets=\(report.counterSets.joined(separator: ","))")
    for pipeline in pipelines {
        print(
            "kernel=\(pipeline.kernel) mode=\(pipeline.mode) operation=\(pipeline.operation) " +
            "simd_width=\(pipeline.threadExecutionWidth) " +
            "max_threads=\(pipeline.maxTotalThreadsPerThreadgroup) " +
            "static_threadgroup_bytes=\(pipeline.staticThreadgroupMemoryBytes) " +
            "benchmark_threads=\(pipeline.benchmarkThreadgroupWidth)"
        )
    }
    print("physical_registers=not_exposed spill_bytes=not_exposed occupancy=not_exposed")
}
