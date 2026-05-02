#pragma once
#include <cstdint>
#include <cstring>

/**
 * @brief Reinterpret a 32-bit word as a single-precision float.
 *
 * Uses memcpy to avoid undefined behaviour from type-punning.
 * Equivalent to std::bit_cast<float>(b) in C++20.
 *
 * @param[in] b  Raw bit pattern to reinterpret.
 * @return       The float whose IEEE 754 representation equals @p b.
 */
inline float    bits_to_float(uint32_t b) { float    f; memcpy(&f, &b, 4); return f; }

/**
 * @brief Reinterpret a single-precision float as its raw 32-bit bit pattern.
 *
 * Uses memcpy to avoid undefined behaviour from type-punning.
 * Equivalent to std::bit_cast<uint32_t>(f) in C++20.
 *
 * @param[in] f  Single-precision float value.
 * @return       32-bit word whose bits match the IEEE 754 representation of @p f.
 */
inline uint32_t float_to_bits(float    f) { uint32_t b; memcpy(&b, &f, 4); return b; }
