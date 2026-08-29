#ifndef VF64_VF64_H
#define VF64_VF64_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VF64_MAGIC UINT32_C(0x56463634)
#define VF64_VERSION_1_0 UINT32_C(0x00010000)
#define VF64_HEADER_WORDS 8u
#define VF64_INSTRUCTION_WORDS 8u
#define VF64_MAX_REGISTERS 32u

typedef uint64_t vf64_slot_t;
typedef uint32_t vf64_flag_mask_t;

typedef struct vf64_program_header {
    uint32_t magic;
    uint32_t version;
    uint32_t instruction_count;
    uint32_t register_count;
    uint32_t input_slots;
    uint32_t output_slots;
    uint32_t lane_count;
    uint32_t feature_bits;
} vf64_program_header;

typedef struct vf64_instruction {
    uint32_t opcode;
    uint32_t destination;
    uint32_t source0;
    uint32_t source1;
    uint32_t source2;
    uint32_t control;
    uint32_t immediate_low;
    uint32_t immediate_high;
} vf64_instruction;

typedef enum vf64_opcode {
    VF64_OP_NOP = 0,
    VF64_OP_HALT = 1,
    VF64_OP_LOAD = 2,
    VF64_OP_STORE = 3,
    VF64_OP_CONSTANT = 4,
    VF64_OP_MOVE = 5,
    VF64_OP_SELECT = 6,
    VF64_OP_FLAGS_CLEAR = 7,
    VF64_OP_FLAGS_GET = 8,
    VF64_OP_LANE_U64 = 9,
    VF64_OP_ADD = 16,
    VF64_OP_SUB = 17,
    VF64_OP_MUL = 18,
    VF64_OP_DIV = 19,
    VF64_OP_SQRT = 20,
    VF64_OP_FMA = 21,
    VF64_OP_REMAINDER = 22,
    VF64_OP_ROUND_TO_INT = 23,
    VF64_OP_EQ = 32,
    VF64_OP_LE = 33,
    VF64_OP_LT = 34,
    VF64_OP_EQ_SIGNALING = 35,
    VF64_OP_LE_QUIET = 36,
    VF64_OP_LT_QUIET = 37,
    VF64_OP_UI32_TO_F64 = 48,
    VF64_OP_UI64_TO_F64 = 49,
    VF64_OP_I32_TO_F64 = 50,
    VF64_OP_I64_TO_F64 = 51,
    VF64_OP_F64_TO_UI32 = 52,
    VF64_OP_F64_TO_UI64 = 53,
    VF64_OP_F64_TO_I32 = 54,
    VF64_OP_F64_TO_I64 = 55,
    VF64_OP_F64_TO_F32 = 56,
    VF64_OP_F64_TO_F16 = 57,
    VF64_OP_F32_TO_F64 = 58,
    VF64_OP_F16_TO_F64 = 59
} vf64_opcode;

typedef enum vf64_precision_mode {
    VF64_MODE_IEEE64 = 0,
    VF64_MODE_FAST48 = 1,
    VF64_MODE_WIDE48 = 2
} vf64_precision_mode;

typedef enum vf64_rounding_mode {
    VF64_ROUND_NEAR_EVEN = 0,
    VF64_ROUND_MIN_MAG = 1,
    VF64_ROUND_MIN = 2,
    VF64_ROUND_MAX = 3,
    VF64_ROUND_NEAR_MAX_MAG = 4
} vf64_rounding_mode;

typedef enum vf64_exception_flag {
    VF64_FLAG_INEXACT = 1u,
    VF64_FLAG_UNDERFLOW = 2u,
    VF64_FLAG_OVERFLOW = 4u,
    VF64_FLAG_INFINITE = 8u,
    VF64_FLAG_INVALID = 16u
} vf64_exception_flag;

#define VF64_CONTROL_ROUND_MASK UINT32_C(0x7)
#define VF64_CONTROL_EXACT UINT32_C(0x8)
#define VF64_CONTROL_MODE_SHIFT 8u
#define VF64_CONTROL_MODE_MASK UINT32_C(0x300)

static inline uint32_t vf64_control(
    vf64_rounding_mode rounding, int exact, vf64_precision_mode mode
) {
    return (uint32_t)rounding | (exact ? VF64_CONTROL_EXACT : 0u) |
           ((uint32_t)mode << VF64_CONTROL_MODE_SHIFT);
}

#if defined(__cplusplus)
static_assert(sizeof(vf64_program_header) == 32, "VF64 header ABI size");
static_assert(sizeof(vf64_instruction) == 32, "VF64 instruction ABI size");
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(vf64_program_header) == 32, "VF64 header ABI size");
_Static_assert(sizeof(vf64_instruction) == 32, "VF64 instruction ABI size");
#endif

#ifdef __cplusplus
}
#endif

#endif
