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


CERTIFIED = "certified-correctly-rounded"
PROVEN = "proven-correctly-rounded"
NO_TIES = (
    "Ties-away-from-zero vectors are derived from MPFR_RNDN plus an exact "
    "midpoint test at 256 bits; {name} of a binary64 is never exactly halfway "
    "between two binary64 values{exception}, so the nearest modes agree "
    "elsewhere"
)

# Per-function policy published with each artifact. Error bounds are the
# derivations in the shader sources and docs/milestones/M9-transcendentals.md.
FUNCTIONS = {
    "f64_exp": {
        "short": "exp", "mpfr": "mpfr_exp", "state": CERTIFIED,
        "bound": "2^-120",
        "ties": NO_TIES.format(name="exp", exception=""),
    },
    "f64_exp2": {
        "short": "exp2", "mpfr": "mpfr_exp2", "state": CERTIFIED,
        "bound": "2^-119.9",
        "ties": NO_TIES.format(
            name="exp2", exception=" except at x = -1075, whose exact result "
            "2^-1075 is the midpoint of 0 and the smallest subnormal and is "
            "rounded exactly"),
    },
    "f64_expm1": {
        "short": "expm1", "mpfr": "mpfr_expm1", "state": CERTIFIED,
        "bound": "2^-118.6",
        "ties": NO_TIES.format(name="expm1", exception=""),
    },
    "f64_log": {
        "short": "log", "mpfr": "mpfr_log", "state": CERTIFIED,
        "bound": "2^-121",
        "ties": NO_TIES.format(name="log", exception=""),
    },
    "f64_log2": {
        "short": "log2", "mpfr": "mpfr_log2", "state": CERTIFIED,
        "bound": "2^-121",
        "ties": NO_TIES.format(name="log2", exception=""),
    },
    "f64_log1p": {
        "short": "log1p", "mpfr": "mpfr_log1p", "state": CERTIFIED,
        "bound": "2^-121",
        "ties": NO_TIES.format(name="log1p", exception=""),
    },
    "f64_cbrt": {
        "short": "cbrt", "mpfr": "mpfr_cbrt", "state": PROVEN,
        "bound": "exact rounding decision",
        "ties": NO_TIES.format(name="cbrt", exception=""),
    },
    "f64_hypot": {
        "short": "hypot", "mpfr": "mpfr_hypot", "state": PROVEN,
        "bound": "exact rounding decision",
        "ties": "Ties-away-from-zero vectors are derived from MPFR_RNDN plus an "
                "exact midpoint test at 256 bits; the corpus includes odd "
                "54-bit Pythagorean hypotenuses, which are real binary64 "
                "midpoints",
    },
    "f64_atan": {
        "short": "atan", "mpfr": "mpfr_atan", "state": CERTIFIED,
        "bound": "2^-120",
        "ties": NO_TIES.format(name="atan", exception=""),
    },
    "f64_asin": {
        "short": "asin", "mpfr": "mpfr_asin", "state": CERTIFIED,
        "bound": "2^-120",
        "ties": NO_TIES.format(name="asin", exception=""),
    },
    "f64_acos": {
        "short": "acos", "mpfr": "mpfr_acos", "state": CERTIFIED,
        "bound": "2^-120",
        "ties": NO_TIES.format(name="acos", exception=""),
    },
    "f64_atan2": {
        "short": "atan2", "mpfr": "mpfr_atan2", "state": CERTIFIED,
        "bound": "2^-120",
        "ties": NO_TIES.format(
            name="atan2", exception=" (for |y/x| < 2^-55 with x > 0 the exact "
            "quotient is rounded by exact integer division, which also settles "
            "every subnormal result)"),
    },
    "f64_pow": {
        "short": "pow", "mpfr": "mpfr_pow", "state": CERTIFIED,
        "bound": "2^-119.8",
        "ties": "Ties-away-from-zero vectors are derived from MPFR_RNDN plus an "
                "exact midpoint test at 256 bits; pow reaches real binary64 "
                "midpoints and exactly representable results (perfect powers "
                "with dyadic y), which are computed and rounded exactly in "
                "integers; every other result is irrational or a non-dyadic "
                "rational and is certified per call",
    },
}


def limitations(policy: dict) -> list:
    entries = []
    if policy["state"] == CERTIFIED:
        entries.append(
            "Correct rounding is established per call by the certification test, "
            "not by a published hardest-to-round search over the whole domain; "
            "every case in this run certified, and an uncertified case would have "
            "failed the run rather than being delivered as proven"
        )
    else:
        entries.append(
            "The rounding decision is made by exact integer comparison against "
            "the rounding boundaries, so it is correct for every argument; this "
            "run tests that implementation against the oracle, and a guess the "
            "bounded correction could not confirm would have been reported "
            "uncertified and failed the run"
        )
    entries.append(policy["ties"])
    entries.append(
        "The corpus is seeded and stratified, not exhaustive; no claim is made "
        "about arguments outside the generated distribution beyond what the "
        "proof-obligation state establishes"
    )
    entries.append(
        f"{policy['short']} is the only function in this artifact; each M9 "
        "function is published in its own artifact"
    )
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--cases", type=int, required=True)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--function", required=True)
    arguments = parser.parse_args()

    policy = FUNCTIONS.get(arguments.function)
    if policy is None:
        print(f"unknown function {arguments.function}", file=sys.stderr)
        return 1
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
            "method": f"{policy['mpfr']} at 53-bit destination precision with the "
                      "binary64 exponent range installed and mpfr_subnormalize "
                      "applied; the reference is the correctly rounded value, not "
                      "an approximation",
            "generator": "tools/m9/m9_ref.c",
            "seed": arguments.seed,
            "random_cases_per_mode": arguments.cases,
        },
        "policy": {
            "function": arguments.function,
            "rounding_modes": [entry["rounding"] for entry in summaries],
            "tininess": "after_rounding",
            "nan_comparison": "bitwise",
            "exception_flags_checked": True,
            "certification_margin_relative": "2^-116" if policy["state"] == CERTIFIED else None,
            "evaluation_error_bound_relative": policy["bound"],
            "proof_obligation_state": policy["state"],
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
        "limitations": limitations(policy),
    }

    destination = repo / "results" / "m9" / (
        f"{stamp}-{device['name'].lower().replace(' ', '-')}-{policy['short']}-level1.json"
    )
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(artifact, indent=2) + "\n")
    print(destination.relative_to(repo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
