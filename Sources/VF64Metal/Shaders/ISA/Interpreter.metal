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

constant uchar vf64_register_bits = 0;
constant uchar vf64_register_fast48 = 1;
constant uchar vf64_register_wide48 = 2;

inline wide_f64 vf64_raw_register(ulong bits) {
    float2 halves = as_type<float2>(bits);
    return make_wide(make_emu(halves.x, halves.y), 0);
}

inline ulong vf64_raw_bits(wide_f64 value) {
    return as_type<ulong>(float2(
        value.significand.hi, value.significand.lo
    ));
}

inline ulong vf64_materialize_register(
    uint index, thread wide_f64 *values, thread uchar *kinds
) {
    if (kinds[index] == vf64_register_fast48) {
        values[index] = vf64_raw_register(pack_binary64(values[index].significand));
    } else if (kinds[index] == vf64_register_wide48) {
        values[index] = vf64_raw_register(wide_pack64(values[index]));
    }
    kinds[index] = vf64_register_bits;
    return vf64_raw_bits(values[index]);
}

inline emu_f64 vf64_fast_register(
    uint index, thread wide_f64 *values, thread uchar *kinds
) {
    if (kinds[index] == vf64_register_fast48) {
        return values[index].significand;
    }
    ulong bits = vf64_materialize_register(index, values, kinds);
    bool ignored;
    return unpack_binary64(bits, ignored);
}

inline wide_f64 vf64_wide_register(
    uint index, thread wide_f64 *values, thread uchar *kinds
) {
    if (kinds[index] == vf64_register_wide48) return values[index];
    if (kinds[index] == vf64_register_fast48) {
        return wide_normalize(make_wide(values[index].significand, 0));
    }
    return wide_unpack64(vf64_raw_bits(values[index]));
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
    wide_f64 registers[32];
    uchar registerKinds[32];
    for (uint index = 0; index < 32; ++index) {
        registers[index] = vf64_raw_register(0ul);
        registerKinds[index] = vf64_register_bits;
    }
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
            registers[destination] = vf64_raw_register(
                inputs[immediateLow * laneCount + gid]
            );
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 3u) {
            outputs[immediateLow * laneCount + gid] = vf64_materialize_register(
                source0, registers, registerKinds
            );
        } else if (opcode == 4u) {
            registers[destination] = vf64_raw_register(
                (ulong(immediateHigh) << 32) | ulong(immediateLow)
            );
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 5u) {
            registers[destination] = registers[source0];
            registerKinds[destination] = registerKinds[source0];
        } else if (opcode == 6u) {
            bool condition = vf64_materialize_register(
                source0, registers, registerKinds
            ) != 0;
            uint selected = condition ? source1 : source2;
            registers[destination] = registers[selected];
            registerKinds[destination] = registerKinds[selected];
        } else if (opcode == 7u) {
            flags = 0;
        } else if (opcode == 8u) {
            registers[destination] = vf64_raw_register(ulong(flags));
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 9u) {
            registers[destination] = vf64_raw_register(ulong(gid));
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode >= 16u && opcode <= 21u) {
            uint mode = vf64_control_mode(control);
            if (mode == vf64_mode_fast48) {
                emu_f64 a = vf64_fast_register(source0, registers, registerKinds);
                emu_f64 result;
                if (opcode == 20u) {
                    result = sqrt_ff(a);
                } else {
                    emu_f64 b = vf64_fast_register(
                        source1, registers, registerKinds
                    );
                    if (opcode == 16u) result = add_ff(a, b);
                    else if (opcode == 17u) result = sub_ff(a, b);
                    else if (opcode == 18u) result = mul_ff(a, b);
                    else if (opcode == 19u) result = div_ff(a, b);
                    else result = fma_ff(
                        a, b, vf64_fast_register(
                            source2, registers, registerKinds
                        )
                    );
                }
                registers[destination] = make_wide(result, 0);
                registerKinds[destination] = vf64_register_fast48;
            } else if (mode == vf64_mode_wide48) {
                wide_f64 a = vf64_wide_register(source0, registers, registerKinds);
                wide_f64 result;
                if (opcode == 20u) {
                    result = wide_sqrt(a);
                } else {
                    wide_f64 b = vf64_wide_register(
                        source1, registers, registerKinds
                    );
                    if (opcode == 16u) result = wide_add(a, b);
                    else if (opcode == 17u) result = wide_sub(a, b);
                    else if (opcode == 18u) result = wide_mul(a, b);
                    else if (opcode == 19u) result = wide_div(a, b);
                    else result = wide_fma(
                        a, b, vf64_wide_register(
                            source2, registers, registerKinds
                        )
                    );
                }
                registers[destination] = result;
                registerKinds[destination] = vf64_register_wide48;
            } else {
                ulong a = vf64_materialize_register(
                    source0, registers, registerKinds
                );
                ulong b = opcode == 20u ? 0ul : vf64_materialize_register(
                    source1, registers, registerKinds
                );
                ulong result;
                if (opcode == 16u) result = soft_add64_status(
                    a, b, vf64_control_rounding(control), flags
                );
                else if (opcode == 17u) result = soft_sub64_status(
                    a, b, vf64_control_rounding(control), flags
                );
                else if (opcode == 18u) result = soft_mul64_status(
                    a, b, vf64_control_rounding(control), flags
                );
                else if (opcode == 19u) result = soft_div64_status(
                    a, b, vf64_control_rounding(control), flags
                );
                else if (opcode == 20u) result = soft_sqrt64_status(
                    a, vf64_control_rounding(control), flags
                );
                else result = soft_fma64_status(
                    a, b, vf64_materialize_register(
                        source2, registers, registerKinds
                    ), vf64_control_rounding(control), flags
                );
                registers[destination] = vf64_raw_register(result);
                registerKinds[destination] = vf64_register_bits;
            }
        } else if (opcode == 22u) {
            ulong result = soft_remainder64_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_materialize_register(source1, registers, registerKinds),
                flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 23u) {
            ulong result = soft_round_to_int64_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_control_rounding(control),
                vf64_control_exact(control), flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 32u || opcode == 35u) {
            ulong result = ulong(soft_equal64_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_materialize_register(source1, registers, registerKinds),
                opcode == 35u, flags
            ));
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode >= 33u && opcode <= 37u) {
            bool orEqual = opcode == 33u || opcode == 36u;
            bool quiet = opcode == 36u || opcode == 37u;
            ulong result = ulong(soft_less64_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_materialize_register(source1, registers, registerKinds),
                orEqual, quiet, flags
            ));
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode >= 48u && opcode <= 51u) {
            ulong raw = vf64_materialize_register(
                source0, registers, registerKinds
            );
            bool signedInput = opcode >= 50u;
            bool width32 = opcode == 48u || opcode == 50u;
            if (width32) raw &= 0xfffffffful;
            bool sign = signedInput && ((raw >> (width32 ? 31u : 63u)) != 0);
            ulong magnitude = sign
                ? ((~raw) + 1ul) & (width32 ? 0xfffffffful : ~0ul) : raw;
            ulong result = soft_uint_to_f64_status(
                magnitude, sign, vf64_control_rounding(control), flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode >= 52u && opcode <= 55u) {
            bool signedTarget = opcode >= 54u;
            uint targetBits = (opcode == 52u || opcode == 54u) ? 32u : 64u;
            ulong result = soft_f64_to_int_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_control_rounding(control),
                vf64_control_exact(control), signedTarget, targetBits, flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 56u || opcode == 57u) {
            bool toF32 = opcode == 56u;
            ulong result = soft_f64_to_format_status(
                vf64_materialize_register(source0, registers, registerKinds),
                vf64_control_rounding(control),
                toF32 ? 8u : 5u, toF32 ? 23u : 10u,
                toF32 ? 127 : 15, flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        } else if (opcode == 58u || opcode == 59u) {
            bool fromF32 = opcode == 58u;
            ulong result = soft_format_to_f64_status(
                vf64_materialize_register(
                    source0, registers, registerKinds
                ) & (fromF32 ? 0xfffffffful : 0xfffful),
                fromF32 ? 8u : 5u, fromF32 ? 23u : 10u,
                fromF32 ? 127 : 15, flags
            );
            registers[destination] = vf64_raw_register(result);
            registerKinds[destination] = vf64_register_bits;
        }
    }
    outputFlags[gid] = flags;
}
