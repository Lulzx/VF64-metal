#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
output_dir=${1:-"$repo_dir/.deps/external-matrices"}

mkdir -p "$output_dir"

fetch() {
    name=$1
    url=$2
    expected=$3
    archive="$output_dir/$name.mtx.gz"
    matrix="$output_dir/$name.mtx"

    curl -L --fail --silent --show-error "$url" -o "$archive"
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        printf 'checksum mismatch for %s: expected %s, got %s\n' \
            "$name" "$expected" "$actual" >&2
        exit 1
    fi
    gzip -dc "$archive" > "$matrix"
    printf 'matrix=%s sha256=%s output=%s\n' "$name" "$actual" "$matrix"
}

fetch bcsstk01 \
    'https://math.nist.gov/MatrixMarket/data/Harwell-Boeing/bcsstruc1/bcsstk01.mtx.gz' \
    '567560f75b952d9c14c0d193ded5d80370d7ca26fe49f9e67deee55f22e55699'
fetch 494_bus \
    'https://math.nist.gov/MatrixMarket/data/Harwell-Boeing/psadmit/494_bus.mtx.gz' \
    '55a2551e699253653e1b297467da1fdb7b647f850b05eb2c6647f8d66a1d8748'

printf 'matrix_market_corpus=pass output_dir=%s\n' "$output_dir"
