
import random

N = 8
DW = 8
ACC_W = 2 * DW + (N - 1).bit_length()
RAW_BEATS = 4
MAX_ROWS = 64
SEED = 0x5A771C

def wrap_signed(value, width):
    mask = (1 << width) - 1
    value &= mask
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value

def pack_lanes(values, width):
    mask = (1 << width) - 1
    return sum(
        (int(value) & mask) << (index * width)
        for index, value in enumerate(values)
    )

def unpack_lanes(value, count, width, signed=True):
    mask = (1 << width) - 1
    lanes = [
        (int(value) >> (index * width)) & mask
        for index in range(count)
    ]
    if signed:
        return [wrap_signed(value, width) for value in lanes]
    return lanes

def random_matrix(rng, rows, cols=N, low=-128, high=127):
    return [
        [rng.randint(low, high) for _ in range(cols)]
        for _ in range(rows)
    ]

def matmul(activations, weights):
    return [
        [
            wrap_signed(
                sum(
                    activations[row][k] * weights[k][col]
                    for k in range(N)
                ),
                ACC_W
            )
            for col in range(N)
        ]
        for row in range(len(activations))
    ]

def golden_i8(activations, weights, shift, rounding, relu):
    accumulators = matmul(activations, weights)
    round_bias = (1 << (shift - 1)) if rounding and shift else 0
    results = []

    for row in accumulators:
        output = []
        for value in row:
            value = (value + round_bias) >> shift
            if relu:
                value = max(value, 0)
            value = max(-128, min(127, value))
            output.append(value)
        results.append(output)
    return results

def golden_raw(activations, weights):
    accumulators = matmul(activations, weights)
    results = []

    for row in accumulators:
        beats = []
        for beat in range(RAW_BEATS):
            low, high = row[2 * beat:2 * beat + 2]
            packed = (
                (low & 0xFFFFFFFF)
                | ((high & 0xFFFFFFFF) << 32)
            )
            beats.append(packed)
        results.append(beats)
    return results

def random_job(rng, count, shift=9, rounding=1, relu=1):
    weights = random_matrix(rng, N)
    activations = random_matrix(rng, count)
    return {
        "weights": weights,
        "activations": activations,
        "expected": golden_i8(
            activations, weights, shift, rounding, relu
        )
    }
