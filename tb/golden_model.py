from typing import Iterable, Sequence

def signed(value: int, width: int) -> int:
    """Interpret the low ``width`` bits as a two's-complement signed value."""
    value &= (1 << width) - 1
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value

def saturate_int8(value: int, relu: bool = False) -> int:
    if relu and value < 0:
        value = 0
    return min(127, max(-128, value))

def requantize(acc: int, shift: int, relu: bool = False) -> int:
    if not 0 <= shift <= 31:
        raise ValueError("shift must be in [0, 31]")
    rounded = acc if shift == 0 else acc + (1 << (shift - 1))
    return saturate_int8(rounded >> shift, relu)


def dot_outputs(
    activations: Sequence[int],
    weights_by_output: Sequence[Sequence[int]],
    biases: Sequence[int] | None = None,
    shift: int = 0,
    relu: bool = False,
    acc_width: int = 24,
) -> list[int]:
    n = len(activations)
    if len(weights_by_output) != n or any(len(row) != n for row in weights_by_output):
        raise ValueError("expected an N-by-N weight matrix")
    if biases is None:
        biases = [0] * n
    if len(biases) != n:
        raise ValueError("bias count must equal output lane count")

    outputs = []
    for col in range(n):
        acc = int(biases[col])
        for row in range(n):
            acc += signed(int(activations[row]), 8) * signed(
                int(weights_by_output[col][row]), 8
            )
        acc = signed(acc, acc_width)
        outputs.append(requantize(acc, shift, relu))
    return outputs


def pack_bytes(values: Iterable[int]) -> int:
    packed = 0
    for lane, value in enumerate(values):
        packed |= (int(value) & 0xFF) << (8 * lane)
    return packed

def unpack_signed_bytes(packed: int, count: int) -> list[int]:
    return [signed((packed >> (8 * lane)) & 0xFF, 8) for lane in range(count)]