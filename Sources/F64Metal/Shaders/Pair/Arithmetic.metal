inline emu_f64 make_emu(float hi, float lo) {
    return emu_f64{hi, lo};
}

inline emu_f64 two_sum(float a, float b) {
    float s = a + b;
    float bb = s - a;
    float e = (a - (s - bb)) + (b - bb);
    return make_emu(s, e);
}

inline emu_f64 quick_two_sum(float a, float b) {
    float s = a + b;
    float e = b - (s - a);
    return make_emu(s, e);
}

inline emu_f64 canonicalize(emu_f64 a) {
    return two_sum(a.hi, a.lo);
}

inline bool emu_is_special(emu_f64 a) {
    return !isfinite(a.hi);
}

inline bool emu_is_zero(emu_f64 a) {
    return a.hi == 0.0f && a.lo == 0.0f;
}

inline emu_f64 special_binary(float a, float b, uint operation) {
    float r = operation == 0 ? a + b : a * b;
    return make_emu(r, 0.0f);
}

inline emu_f64 add_ff(emu_f64 a, emu_f64 b) {
    if (emu_is_special(a) || emu_is_special(b)) {
        return special_binary(a.hi, b.hi, 0);
    }
    if (emu_is_zero(a) && emu_is_zero(b)) {
        return make_emu(a.hi + b.hi, 0.0f);
    }

    emu_f64 s = two_sum(a.hi, b.hi);
    emu_f64 t = two_sum(a.lo, b.lo);
    float correction = s.lo + t.hi;
    emu_f64 u = quick_two_sum(s.hi, correction);
    return quick_two_sum(u.hi, u.lo + t.lo);
}

inline emu_f64 neg_ff(emu_f64 a) {
    return make_emu(-a.hi, -a.lo);
}

inline emu_f64 sub_ff(emu_f64 a, emu_f64 b) {
    return add_ff(a, neg_ff(b));
}

inline emu_f64 mul_ff(emu_f64 a, emu_f64 b) {
    if (emu_is_special(a) || emu_is_special(b)) {
        return special_binary(a.hi, b.hi, 1);
    }
    if (emu_is_zero(a) || emu_is_zero(b)) {
        return make_emu(a.hi * b.hi, 0.0f);
    }

    float p = a.hi * b.hi;
    float e = fma(a.hi, b.hi, -p);
    e = fma(a.hi, b.lo, e);
    e = fma(a.lo, b.hi, e);
    e = fma(a.lo, b.lo, e);
    return quick_two_sum(p, e);
}

// Research variants used by the benchmark runner. The shortened form omits the
// low*low term; the Dekker form measures the cost of operand splitting when an
// explicit correctly-rounded FP32 FMA is available.
inline emu_f64 mul_ff_short(emu_f64 a, emu_f64 b) {
    float p = a.hi * b.hi;
    float e = fma(a.hi, b.hi, -p);
    e = fma(a.hi, b.lo, e);
    e = fma(a.lo, b.hi, e);
    return quick_two_sum(p, e);
}

inline float dekker_product_error(float a, float b, float product) {
    constexpr float splitter = 4097.0f;
    float ca = splitter * a;
    float aBig = ca - a;
    float aHi = ca - aBig;
    float aLo = a - aHi;
    float cb = splitter * b;
    float bBig = cb - b;
    float bHi = cb - bBig;
    float bLo = b - bHi;
    return ((aHi * bHi - product) + aHi * bLo + aLo * bHi) + aLo * bLo;
}

inline emu_f64 mul_ff_dekker(emu_f64 a, emu_f64 b) {
    float p = a.hi * b.hi;
    float e = dekker_product_error(a.hi, b.hi, p);
    e += a.hi * b.lo;
    e += a.lo * b.hi;
    e += a.lo * b.lo;
    return quick_two_sum(p, e);
}

inline emu_f64 fma_ff(emu_f64 a, emu_f64 b, emu_f64 c) {
    if (emu_is_special(a) || emu_is_special(b) || emu_is_special(c)) {
        return make_emu(fma(a.hi, b.hi, c.hi), 0.0f);
    }

    // Retain the exact high product residual and all cross terms, then perform
    // one accurate addition. This avoids materializing a packed product.
    float p = a.hi * b.hi;
    float e = fma(a.hi, b.hi, -p);
    e = fma(a.hi, b.lo, e);
    e = fma(a.lo, b.hi, e);
    e = fma(a.lo, b.lo, e);
    return add_ff(quick_two_sum(p, e), c);
}

inline emu_f64 div_ff(emu_f64 a, emu_f64 b) {
    if (emu_is_special(a) || emu_is_special(b) || b.hi == 0.0f) {
        return make_emu(a.hi / b.hi, 0.0f);
    }
    float q1 = a.hi / b.hi;
    emu_f64 r = sub_ff(a, mul_ff(b, make_emu(q1, 0.0f)));
    float q2 = (r.hi + r.lo) / b.hi;
    emu_f64 q = quick_two_sum(q1, q2);
    r = sub_ff(a, mul_ff(b, q));
    float q3 = (r.hi + r.lo) / b.hi;
    return add_ff(q, make_emu(q3, 0.0f));
}

inline emu_f64 div_ff_one_correction(emu_f64 a, emu_f64 b) {
    if (emu_is_special(a) || emu_is_special(b) || b.hi == 0.0f) {
        return make_emu(a.hi / b.hi, 0.0f);
    }
    float q1 = a.hi / b.hi;
    emu_f64 r = sub_ff(a, mul_ff(b, make_emu(q1, 0.0f)));
    float q2 = (r.hi + r.lo) / b.hi;
    return quick_two_sum(q1, q2);
}

inline emu_f64 sqrt_ff(emu_f64 a) {
    if (emu_is_special(a) || a.hi <= 0.0f) {
        return make_emu(sqrt(a.hi), 0.0f);
    }
    float root = sqrt(a.hi);
    emu_f64 residual = sub_ff(a, mul_ff(
        make_emu(root, 0.0f), make_emu(root, 0.0f)
    ));
    float correction = (residual.hi + residual.lo) / (2.0f * root);
    return quick_two_sum(root, correction);
}
