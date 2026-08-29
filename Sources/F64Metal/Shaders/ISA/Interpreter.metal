constant uint vf64_mode_ieee64 = 0u;
constant uint vf64_mode_fast48 = 1u;
constant uint vf64_mode_wide48 = 2u;

inline uint vf64_control_rounding(uint control) { return control & 7u; }
inline uint vf64_control_mode(uint control) { return (control >> 8) & 3u; }
inline bool vf64_control_exact(uint control) { return (control & 8u) != 0; }

inline ulong vf64_add_value(
    ulong a, ulong b, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(add_ff(
            unpack_binary64(a, ignored), unpack_binary64(b, ignored)
        ));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_add(wide_unpack64(a), wide_unpack64(b)));
    }
    return soft_add64_status(a, b, vf64_control_rounding(control), flags);
}

inline ulong vf64_sub_value(
    ulong a, ulong b, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(sub_ff(
            unpack_binary64(a, ignored), unpack_binary64(b, ignored)
        ));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_sub(wide_unpack64(a), wide_unpack64(b)));
    }
    return soft_sub64_status(a, b, vf64_control_rounding(control), flags);
}

inline ulong vf64_mul_value(
    ulong a, ulong b, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(mul_ff(
            unpack_binary64(a, ignored), unpack_binary64(b, ignored)
        ));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_mul(wide_unpack64(a), wide_unpack64(b)));
    }
    return soft_mul64_status(a, b, vf64_control_rounding(control), flags);
}

inline ulong vf64_div_value(
    ulong a, ulong b, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(div_ff(
            unpack_binary64(a, ignored), unpack_binary64(b, ignored)
        ));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_div(wide_unpack64(a), wide_unpack64(b)));
    }
    return soft_div64_status(a, b, vf64_control_rounding(control), flags);
}

inline ulong vf64_sqrt_value(
    ulong a, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(sqrt_ff(unpack_binary64(a, ignored)));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_sqrt(wide_unpack64(a)));
    }
    return soft_sqrt64_status(a, vf64_control_rounding(control), flags);
}

inline ulong vf64_fma_value(
    ulong a, ulong b, ulong c, uint control, thread uint &flags
) {
    uint mode = vf64_control_mode(control);
    if (mode == vf64_mode_fast48) {
        bool ignored;
        return pack_binary64(fma_ff(
            unpack_binary64(a, ignored), unpack_binary64(b, ignored),
            unpack_binary64(c, ignored)
        ));
    }
    if (mode == vf64_mode_wide48) {
        return wide_pack64(wide_fma(
            wide_unpack64(a), wide_unpack64(b), wide_unpack64(c)
        ));
    }
    return soft_fma64_status(
        a, b, c, vf64_control_rounding(control), flags
    );
}

kernel void vf64_interpreter_kernel(
    device const uint *program [[buffer(0)]],
    device const ulong *inputs [[buffer(1)]],
    device ulong *outputs [[buffer(2)]],
    device uint *outputFlags [[buffer(3)]],
    constant uint &dispatchCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    uint laneCount = program[6];
    if (gid >= dispatchCount || gid >= laneCount) return;
    uint instructionCount = program[2];
    ulong registers[32];
    for (uint index = 0; index < 32; ++index) registers[index] = 0ul;
    uint flags = 0;

    for (uint pc = 0; pc < instructionCount; ++pc) {
        uint base = 8u + pc * 8u;
        uint opcode = program[base];
        uint destination = program[base + 1u];
        uint source0 = program[base + 2u];
        uint source1 = program[base + 3u];
        uint source2 = program[base + 4u];
        uint control = program[base + 5u];
        uint immediateLow = program[base + 6u];
        uint immediateHigh = program[base + 7u];

        if (opcode == 0u) continue;
        if (opcode == 1u) break;
        if (opcode == 2u) {
            registers[destination] = inputs[immediateLow * laneCount + gid];
        } else if (opcode == 3u) {
            outputs[immediateLow * laneCount + gid] = registers[source0];
        } else if (opcode == 4u) {
            registers[destination] =
                (ulong(immediateHigh) << 32) | ulong(immediateLow);
        } else if (opcode == 5u) {
            registers[destination] = registers[source0];
        } else if (opcode == 6u) {
            registers[destination] = registers[source0] != 0
                ? registers[source1] : registers[source2];
        } else if (opcode == 7u) {
            flags = 0;
        } else if (opcode == 8u) {
            registers[destination] = ulong(flags);
        } else if (opcode == 9u) {
            registers[destination] = ulong(gid);
        } else if (opcode == 16u) {
            registers[destination] = vf64_add_value(
                registers[source0], registers[source1], control, flags
            );
        } else if (opcode == 17u) {
            registers[destination] = vf64_sub_value(
                registers[source0], registers[source1], control, flags
            );
        } else if (opcode == 18u) {
            registers[destination] = vf64_mul_value(
                registers[source0], registers[source1], control, flags
            );
        } else if (opcode == 19u) {
            registers[destination] = vf64_div_value(
                registers[source0], registers[source1], control, flags
            );
        } else if (opcode == 20u) {
            registers[destination] = vf64_sqrt_value(
                registers[source0], control, flags
            );
        } else if (opcode == 21u) {
            registers[destination] = vf64_fma_value(
                registers[source0], registers[source1], registers[source2],
                control, flags
            );
        } else if (opcode == 22u) {
            registers[destination] = soft_remainder64_status(
                registers[source0], registers[source1], flags
            );
        } else if (opcode == 23u) {
            registers[destination] = soft_round_to_int64_status(
                registers[source0], vf64_control_rounding(control),
                vf64_control_exact(control), flags
            );
        } else if (opcode == 32u || opcode == 35u) {
            registers[destination] = ulong(soft_equal64_status(
                registers[source0], registers[source1], opcode == 35u, flags
            ));
        } else if (opcode >= 33u && opcode <= 37u) {
            bool orEqual = opcode == 33u || opcode == 36u;
            bool quiet = opcode == 36u || opcode == 37u;
            registers[destination] = ulong(soft_less64_status(
                registers[source0], registers[source1], orEqual, quiet, flags
            ));
        } else if (opcode >= 48u && opcode <= 51u) {
            ulong raw = registers[source0];
            bool signedInput = opcode >= 50u;
            bool width32 = opcode == 48u || opcode == 50u;
            if (width32) raw &= 0xfffffffful;
            bool sign = signedInput && ((raw >> (width32 ? 31u : 63u)) != 0);
            ulong magnitude = sign
                ? ((~raw) + 1ul) & (width32 ? 0xfffffffful : ~0ul) : raw;
            registers[destination] = soft_uint_to_f64_status(
                magnitude, sign, vf64_control_rounding(control), flags
            );
        } else if (opcode >= 52u && opcode <= 55u) {
            bool signedTarget = opcode >= 54u;
            uint targetBits = (opcode == 52u || opcode == 54u) ? 32u : 64u;
            registers[destination] = soft_f64_to_int_status(
                registers[source0], vf64_control_rounding(control),
                vf64_control_exact(control), signedTarget, targetBits, flags
            );
        } else if (opcode == 56u || opcode == 57u) {
            bool toF32 = opcode == 56u;
            registers[destination] = soft_f64_to_format_status(
                registers[source0], vf64_control_rounding(control),
                toF32 ? 8u : 5u, toF32 ? 23u : 10u,
                toF32 ? 127 : 15, flags
            );
        } else if (opcode == 58u || opcode == 59u) {
            bool fromF32 = opcode == 58u;
            registers[destination] = soft_format_to_f64_status(
                registers[source0] & (fromF32 ? 0xfffffffful : 0xfffful),
                fromF32 ? 8u : 5u, fromF32 ? 23u : 10u,
                fromF32 ? 127 : 15, flags
            );
        }
    }
    outputFlags[gid] = flags;
}
