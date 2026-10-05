#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
binary="$repo_dir/.build/release/vf64-metal"

if [ ! -x "$binary" ]; then
    printf 'release binary missing: %s\n' "$binary" >&2
    exit 1
fi

text=$($binary version)
json=$($binary version --json)
[ "$text" = "vf64-metal 0.9.0-dev (VF64 ABI 1.0)" ]
[ "$json" = '{"tool":"0.9.0-dev","vf64_abi":"1.0","vf64_binary_version":"0x10000"}' ]

# M9 transcendentals have no VF64 v1 opcode; every mode must refuse them.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for function in exp exp2 expm1 log log2 log1p cbrt hypot pow atan atan2 \
    asin acos sin cos tan sinh cosh tanh asinh acosh atanh; do
    case $function in
        hypot|pow|atan2) call="$function(x, y)" ;;
        *) call="$function(x)" ;;
    esac
    printf 'kernel k(double x, double y, double z) -> double {\n    return %s;\n}\n' \
        "$call" >"$work/k.vf64"
    expected="transcendental '$function' has no VF64 v1 opcode"
    for mode in fast48 wide48 ieee64 auto; do
        if [ "$mode" = auto ]; then
            set -- --fp64=auto --accuracy-bits=40 \
                --profile="$repo_dir/examples/axpy-profile.json" \
                --diagnostics="$work/diagnostics.json"
        else
            set -- --fp64="$mode"
        fi
        rm -f "$work/k.bin"
        if output=$("$binary" vf64-compile "$@" --lanes=64 \
            "$work/k.vf64" "$work/k.bin" 2>&1); then
            printf 'vf64-compile accepted %s under %s\n' "$function" "$mode" >&2
            exit 1
        fi
        case $output in
            *"$expected"*) ;;
            *)
                printf 'vf64-compile %s under %s: unexpected diagnostic: %s\n' \
                    "$function" "$mode" "$output" >&2
                exit 1
                ;;
        esac
        [ ! -e "$work/k.bin" ]
    done
done

printf 'vf64_cli_api=pass\n'
