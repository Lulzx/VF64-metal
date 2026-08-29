#!/usr/bin/env python3
"""Summarize selected device-level Metal counters during labeled VF64 GPU work."""

import bisect
import json
import re
import statistics
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


WANTED = {
    "Kernel Occupancy",
    "L1 Register Residency",
    "Compute SIMD Groups Inflight",
}


def die(message):
    raise SystemExit(f"error: {message}")


def resolved_rows(path):
    references = {}
    for _, element in ET.iterparse(path, events=("end",)):
        if element.tag != "row":
            continue
        values = []
        for cell in element:
            reference = cell.attrib.get("ref")
            if reference is not None:
                value = references.get(reference, "")
            elif cell.tag in ("process", "formatted-label"):
                value = cell.attrib.get("fmt", "")
            else:
                value = "".join(cell.itertext()).strip()
            identifier = cell.attrib.get("id")
            if identifier is not None:
                references[identifier] = value
            for nested in cell.iter():
                nested_id = nested.attrib.get("id")
                if nested_id is None or nested is cell:
                    continue
                if nested.tag in ("process", "formatted-label"):
                    nested_value = nested.attrib.get("fmt", "")
                else:
                    nested_value = "".join(nested.itertext()).strip()
                references[nested_id] = nested_value
            values.append(value)
        yield values
        element.clear()


def schema_columns(path):
    document = ET.parse(path)
    return [node.text for node in document.findall("./node/schema/col/mnemonic")]


def load_counter_info(path):
    columns = schema_columns(path)
    counters = {}
    for values in resolved_rows(path):
        row = dict(zip(columns, values))
        if row.get("name") in WANTED:
            counters[int(row["counter-id"])] = {
                "name": row["name"],
                "description": row["description"],
                "type": row["type"],
            }
    missing = WANTED.difference(item["name"] for item in counters.values())
    if missing:
        die("counter profile is missing: " + ", ".join(sorted(missing)))
    return counters


def load_intervals(path):
    columns = schema_columns(path)
    intervals = []
    label_pattern = re.compile(r"vf64:[A-Za-z0-9_]+")
    for values in resolved_rows(path):
        row = dict(zip(columns, values))
        if "vf64-metal" not in row.get("process", ""):
            continue
        if row.get("channel-name") != "Compute":
            continue
        match = label_pattern.search(row.get("event-label", ""))
        if match is None:
            continue
        start = int(row["start"])
        intervals.append((start, start + int(row["duration"]), match.group(0)))
    intervals.sort()
    if not intervals:
        die("no labeled VF64 compute intervals found")
    return intervals


def summarize(values):
    ordered = sorted(values)
    return {
        "sample_count": len(ordered),
        "minimum": min(ordered),
        "median": statistics.median(ordered),
        "mean": statistics.fmean(ordered),
        "maximum": max(ordered),
    }


def stream_counter_values(path, counters, intervals):
    starts = [item[0] for item in intervals]
    references = [{}, {}, {}]
    per_label = defaultdict(lambda: defaultdict(list))
    unmatched = defaultdict(int)
    ambiguous = 0

    for _, element in ET.iterparse(path, events=("end",)):
        if element.tag != "row":
            continue
        cells = list(element)
        resolved = []
        for position, cell in enumerate(cells[:3]):
            reference = cell.attrib.get("ref")
            if reference is not None:
                value = references[position].get(reference)
            else:
                value = "".join(cell.itertext()).strip()
            identifier = cell.attrib.get("id")
            if identifier is not None and value is not None:
                references[position][identifier] = value
            resolved.append(value)
        element.clear()
        if len(resolved) != 3 or resolved[1] is None:
            continue
        counter_id = int(resolved[1])
        if counter_id not in counters:
            continue
        if resolved[0] is None or resolved[2] is None:
            die("unresolved reference in selected counter row")
        timestamp = int(resolved[0])
        index = bisect.bisect_right(starts, timestamp) - 1
        matches = []
        while index >= 0 and intervals[index][0] <= timestamp:
            start, end, label = intervals[index]
            if end < timestamp:
                break
            matches.append(label)
            index -= 1
        name = counters[counter_id]["name"]
        if not matches:
            unmatched[name] += 1
            continue
        if len(matches) > 1:
            ambiguous += 1
        for label in set(matches):
            per_label[label][name].append(float(resolved[2]))

    result = []
    interval_counts = defaultdict(int)
    for _, _, label in intervals:
        interval_counts[label] += 1
    for label in sorted(interval_counts):
        metrics = {
            name: summarize(samples)
            for name, samples in sorted(per_label[label].items())
            if samples
        }
        result.append({
            "label": label,
            "gpu_interval_count": interval_counts[label],
            "counters": metrics,
        })
    emitted = {
        name
        for metrics in per_label.values()
        for name, samples in metrics.items()
        if samples
    }
    missing = WANTED.difference(emitted)
    if missing:
        die("selected counter rows were not emitted during VF64 intervals: " + ", ".join(sorted(missing)))
    return result, dict(sorted(unmatched.items())), ambiguous


if len(sys.argv) != 4:
    die("usage: summarize-metal-counters.py COUNTER_INFO_XML COUNTER_VALUES_XML GPU_INTERVALS_XML")

counter_info = load_counter_info(sys.argv[1])
gpu_intervals = load_intervals(sys.argv[3])
pipelines, unmatched_samples, ambiguous_samples = stream_counter_values(
    sys.argv[2], counter_info, gpu_intervals
)

output = {
    "counter_definitions": sorted(counter_info.values(), key=lambda item: item["name"]),
    "labeled_gpu_interval_count": len(gpu_intervals),
    "pipelines": pipelines,
    "unmatched_device_samples": unmatched_samples,
    "samples_overlapping_multiple_vf64_intervals": ambiguous_samples,
    "scope": "Device-level counters sampled during labeled VF64 compute intervals",
}
json.dump(output, sys.stdout, indent=2, sort_keys=True)
sys.stdout.write("\n")
