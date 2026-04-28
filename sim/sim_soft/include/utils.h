#pragma once
#include <cstdint>
#include <cstring>

/* Bit-accurate float <-> uint32_t. memcpy is the only defined way to do this in C++. */
inline float    bits_to_float(uint32_t b) { float    f; memcpy(&f, &b, 4); return f; }
inline uint32_t float_to_bits(float    f) { uint32_t b; memcpy(&b, &f, 4); return b; }
