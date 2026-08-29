#include "vf64/vf64.h"

#include <assert.h>

int main(void) {
    assert(VF64_MAGIC == UINT32_C(0x56463634));
    assert(VF64_VERSION_1_0 == UINT32_C(0x00010000));
    assert(sizeof(vf64_slot_t) == 8);
    assert(sizeof(vf64_flag_mask_t) == 4);
    assert(sizeof(vf64_program_header) == VF64_HEADER_WORDS * 4);
    assert(sizeof(vf64_instruction) == VF64_INSTRUCTION_WORDS * 4);
    assert(offsetof(vf64_program_header, feature_bits) == 28);
    assert(offsetof(vf64_instruction, immediate_high) == 28);
    assert(VF64_OP_NOP == 0 && VF64_OP_HALT == 1 && VF64_OP_LOAD == 2 &&
           VF64_OP_STORE == 3 && VF64_OP_CONSTANT == 4 && VF64_OP_MOVE == 5 &&
           VF64_OP_SELECT == 6 && VF64_OP_FLAGS_CLEAR == 7 &&
           VF64_OP_FLAGS_GET == 8 && VF64_OP_LANE_U64 == 9);
    assert(VF64_OP_ADD == 16 && VF64_OP_SUB == 17 && VF64_OP_MUL == 18 &&
           VF64_OP_DIV == 19 && VF64_OP_SQRT == 20 && VF64_OP_FMA == 21 &&
           VF64_OP_REMAINDER == 22 && VF64_OP_ROUND_TO_INT == 23);
    assert(VF64_OP_EQ == 32 && VF64_OP_LE == 33 && VF64_OP_LT == 34 &&
           VF64_OP_EQ_SIGNALING == 35 && VF64_OP_LE_QUIET == 36 &&
           VF64_OP_LT_QUIET == 37);
    assert(VF64_OP_UI32_TO_F64 == 48 && VF64_OP_UI64_TO_F64 == 49 &&
           VF64_OP_I32_TO_F64 == 50 && VF64_OP_I64_TO_F64 == 51 &&
           VF64_OP_F64_TO_UI32 == 52 && VF64_OP_F64_TO_UI64 == 53 &&
           VF64_OP_F64_TO_I32 == 54 && VF64_OP_F64_TO_I64 == 55 &&
           VF64_OP_F64_TO_F32 == 56 && VF64_OP_F64_TO_F16 == 57 &&
           VF64_OP_F32_TO_F64 == 58 && VF64_OP_F16_TO_F64 == 59);
    assert(VF64_MODE_IEEE64 == 0 && VF64_MODE_FAST48 == 1 &&
           VF64_MODE_WIDE48 == 2);
    assert(VF64_FLAG_INEXACT == 1 && VF64_FLAG_INVALID == 16);
    assert(VF64_ROUND_NEAR_EVEN == 0 && VF64_ROUND_MIN_MAG == 1 &&
           VF64_ROUND_MIN == 2 && VF64_ROUND_MAX == 3 &&
           VF64_ROUND_NEAR_MAX_MAG == 4);
    assert(vf64_control(VF64_ROUND_MAX, 1, VF64_MODE_WIDE48) ==
           UINT32_C(0x20b));
    return 0;
}
