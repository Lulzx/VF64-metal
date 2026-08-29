#!/usr/bin/env swift

import Foundation

struct TraceTable {
    let columns: [String]
    let rows: [[String: String]]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func loadTable(at path: String) -> TraceTable {
    guard let document = try? XMLDocument(contentsOf: URL(fileURLWithPath: path)) else {
        fail("cannot read XML table at \(path)")
    }

    let columnNodes = (try? document.nodes(forXPath: "/trace-query-result/node/schema/col/mnemonic")) ?? []
    let columns = columnNodes.compactMap(\.stringValue)
    guard !columns.isEmpty else { fail("no schema columns in \(path)") }

    let rowNodes = (try? document.nodes(forXPath: "/trace-query-result/node/row")) ?? []
    var references: [String: String] = [:]
    var rows: [[String: String]] = []

    for rowNode in rowNodes {
        guard let row = rowNode as? XMLElement else { continue }
        var values: [String] = []
        for cellNode in row.children ?? [] {
            guard let cell = cellNode as? XMLElement else { continue }
            let id = cell.attribute(forName: "id")?.stringValue
            let reference = cell.attribute(forName: "ref")?.stringValue
            let value: String
            if let reference {
                value = references[reference] ?? ""
            } else {
                if cell.name == "process", let formatted = cell.attribute(forName: "fmt")?.stringValue {
                    value = formatted
                } else {
                    value = cell.stringValue ?? ""
                }
                if let id { references[id] = value }
            }
            values.append(value)
        }

        var result: [String: String] = [:]
        for (index, column) in columns.enumerated() where index < values.count {
            result[column] = values[index]
        }
        rows.append(result)
    }
    return TraceTable(columns: columns, rows: rows)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: summarize-metal-trace.swift ENCODERS_XML SPILLS_XML")
}

let encoders = loadTable(at: CommandLine.arguments[1])
let spills = loadTable(at: CommandLine.arguments[2])
var labelsByEncoder: [String: String] = [:]
var encoderInstancesByLabel: [String: Set<String>] = [:]

for row in encoders.rows {
    guard let encoderID = row["encoder-id"],
          let label = row["encoder-label"],
          label.hasPrefix("vf64:") else { continue }
    labelsByEncoder[encoderID] = label
    encoderInstancesByLabel[label, default: []].insert(encoderID)
}

struct PipelineAggregate {
    var spillEventCount = 0
    var maximumSpilledBytes = 0
    var totalSpilledBytes = 0
}

var aggregates: [String: PipelineAggregate] = [:]
var targetSpillEventCount = 0
var unmappedSpillEventCount = 0

for row in spills.rows {
    guard row["process"]?.contains("vf64-metal") == true else { continue }
    targetSpillEventCount += 1
    guard let encoderID = row["encoder-id"],
          let label = labelsByEncoder[encoderID],
          let bytesText = row["spilled-bytes"],
          let bytes = Int(bytesText) else {
        unmappedSpillEventCount += 1
        continue
    }
    var aggregate = aggregates[label, default: PipelineAggregate()]
    aggregate.spillEventCount += 1
    aggregate.maximumSpilledBytes = max(aggregate.maximumSpilledBytes, bytes)
    aggregate.totalSpilledBytes += bytes
    aggregates[label] = aggregate
}

let labels = Set(encoderInstancesByLabel.keys).union(aggregates.keys).sorted()
let pipelines: [[String: Any]] = labels.map { label in
    let aggregate = aggregates[label, default: PipelineAggregate()]
    return [
        "label": label,
        "encoder_instances": encoderInstancesByLabel[label]?.count ?? 0,
        "spill_event_count": aggregate.spillEventCount,
        "maximum_spilled_bytes": aggregate.maximumSpilledBytes,
        "total_spilled_bytes_across_dispatches": aggregate.totalSpilledBytes,
    ]
}

let output: [String: Any] = [
    "labeled_encoder_instances": labelsByEncoder.count,
    "target_spill_event_count": targetSpillEventCount,
    "unmapped_spill_event_count": unmappedSpillEventCount,
    "pipelines": pipelines,
]

guard JSONSerialization.isValidJSONObject(output),
      let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) else {
    fail("cannot encode trace summary")
}
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
