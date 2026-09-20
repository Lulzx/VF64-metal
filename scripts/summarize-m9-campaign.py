#!/usr/bin/env python3
"""Compose the M9 conformance artifact from a completed campaign.

Reads the per-rounding-mode summaries emitted by `vf64-metal transcendental`
plus the device and oracle provenance captured by run-mpfr-m9.sh, and writes
one machine-readable artifact under results/m9/. Fails closed: a run with any
mismatch, any uncertified case, or any malformed line does not produce an
artifact.
"""
import argparse
import datetime
import json
import pathlib
import re
import sys


def gpu_details(text: str) -> dict:
    chipset = re.search(r"Chipset Model: (.+)", text)
    cores = re.search(r"Total Number of Cores: (\d+)", text)
    metal = re.search(r"Metal Support: (.+)", text)
    return {
        "name": chipset.group(1).strip() if chipset else "unknown",
        "gpu_cores": int(cores.group(1)) if cores else 0,
        "metal": metal.group(1).strip() if metal else "unknown",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--cases", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--function", required=True)
    arguments = parser.parse_args()

    work = pathlib.Path(arguments.work)
    repo = pathlib.Path(arguments.repo)

    summaries = [
        json.loads(line)
        for line in (work / "summaries.jsonl").read_text().splitlines()
        if line.strip()
    ]
    if len(summaries) != 5:
        print(f"expected 5 rounding modes, found {len(summaries)}", file=sys.stderr)
        return 1

    total = sum(entry["cases"] for entry in summaries)
    mismatches = sum(entry["mismatches"] for entry in summaries)
    uncertified = sum(entry["uncertified"] for entry in summaries)
    malformed = sum(entry["malformed"] for entry in summaries)
    if mismatches or uncertified or malformed:
        print(
            f"campaign not clean: {mismatches} mismatches, "
            f"{uncertified} uncertified, {malformed} malformed",
            file=sys.stderr,
        )
        return 1

    versions = (work / "sw_vers.txt").read_text()
    product = re.search(r"ProductVersion:\s*(\S+)", versions)
    build = re.search(r"BuildVersion:\s*(\S+)", versions)
    device = gpu_details((work / "gpu.txt").read_text())
    device["os"] = f"macOS {product.group(1) if product else 'unknown'}"
    device["os_build"] = build.group(1) if build else "unknown"

    commit = (work / "commit.txt").read_text().strip()
    mpfr_version = (work / "mpfr.txt").read_text().strip()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    artifact = {
        "schema_version": 1,
        "milestone": "M9",
        "result_scope": "binary64 result bits, exception flags, and per-call certification",
        "status": "pass",
        "unexplained_mismatches": 0,
        "uncertified_results": 0,
        "source_commit": commit,
        "command": "scripts/run-mpfr-m9.sh",
        "oracle": {
            "name": "GNU MPFR",
            "mpfr_version": mpfr_version,
            "method": "mpfr_exp at 53-bit destination precision with the binary64 "
                      "exponent range installed and mpfr_subnormalize applied; the "
                      "reference is the correctly rounded value, not an approximation",
            "generator": "tools/m9/exp_ref.c",
            "seed": arguments.seed,
            "random_cases_per_mode": arguments.cases,
        },
        "policy": {
            "function": arguments.function,
            "rounding_modes": [entry["rounding"] for entry in summaries],
            "tininess": "after_rounding",
            "nan_comparison": "bitwise",
            "exception_flags_checked": True,
            "certification_margin_relative": "2^-116",
            "evaluation_error_bound_relative": "2^-120",
            "proof_obligation_state": "certified-correctly-rounded",
        },
        "device": device,
        "rounding_modes": {
            entry["rounding"]: {
                "cases": entry["cases"],
                "mismatches": entry["mismatches"],
                "uncertified": entry["uncertified"],
                "oracle_flagged": entry["oracle_flagged"],
            }
            for entry in summaries
        },
        "total_result_comparisons": total,
        "limitations": [
            "Correct rounding is established per call by the certification test, "
            "not by a published hardest-to-round search over the whole domain; "
            "every case in this run certified, and an uncertified case would have "
            "failed the run rather than being delivered as proven",
            "Ties-away-from-zero vectors are generated with MPFR_RNDN; exp(x) is "
            "never exactly halfway between two binary64 values for nonzero x, so "
            "the two nearest modes cannot disagree",
            "The corpus is seeded and stratified, not exhaustive; no claim is made "
            "about arguments outside the generated distribution beyond what the "
            "certification test establishes per call",
            "exp is the only function in this artifact; no other transcendental is "
            "implemented or claimed",
        ],
    }

    destination = repo / "results" / "m9" / (
        f"{stamp}-{device['name'].lower().replace(' ', '-')}-exp-level1.json"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(artifact, indent=2) + "\n")
    print(destination.relative_to(repo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
