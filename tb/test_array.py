import random
import cocotb
from generic import pulse_clock, wrap_signed

N = 8
DW = 8
ACC_W = 24
SEED = 42

def pack(values, width):
    result = 0
    mask = (1 << width) - 1
    for i, value in enumerate(values):
        result |= (value & mask) << (i * width)
    return result

def unpack(signal, count, width):
    value = int(signal.value)
    mask = (1 << width) - 1
    return [wrap_signed((value >> (i * width)) & mask, width) for i in range(count)]


@cocotb.test()
async def test_array(dut):
    rng = random.Random(SEED)

    dut.i_clk_w.value = 0
    dut.i_clk_adv.value = 0

    weights = [rng.randint(-128, 127) for _ in range(N)]
    activations = [rng.randint(-128, 127) for _ in range(N)]
    biases = [rng.randint(-1000, 1000) for _ in range(N)]

    dut.i_w_top.value = pack(weights, DW)
    dut.i_a_left.value = pack(activations, DW)
    dut.i_psum_top.value = pack(biases, ACC_W)

    for _ in range(N):
        await pulse_clock(dut.i_clk_w)

    for _ in range(3 * N):
        await pulse_clock(dut.i_clk_adv)

    expected = [wrap_signed(biases[col] + sum(activations[row] * weights[col] for row in range(N)), ACC_W,) for col in range(N)]
    actual = unpack(dut.o_c_bottom, N, ACC_W)
    assert actual == expected, (f"Expected: {expected}\n" f"Actual: {actual}")

    dut._log.info("Array test passed: %d columns, seed=%d", N, SEED)