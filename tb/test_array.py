import random
import cocotb
from helper.generic import pack_signed_lanes, pulse_clock, unpack_signed_lanes, wrap_signed

N = 8
DW = 8
ACC_W = 24
SEED = 42

def reference(activations, weights, biases):
    return [wrap_signed(biases[col] + sum(activations[row] * weights[row][col] for row in range(N)), ACC_W,) for col in range(N)]

@cocotb.test()
async def test_array_matrix_vector(dut):
    rng = random.Random(SEED)
    dut.i_clk_w.value = 0
    dut.i_clk_adv.value = 0
    dut.i_w_stream.value = 0
    dut.i_a_left.value = 0
    dut.i_psum_top.value = 0

    weights = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(N)]
    activations = [rng.randint(-128, 127) for _ in range(N)]
    biases = [rng.randint(-1000, 1000) for _ in range(N)]

    for row in weights:
        dut.i_w_stream.value = pack_signed_lanes(row, DW)
        await pulse_clock(dut.i_clk_w)

    for _ in range(2 * N + 2):
        await pulse_clock(dut.i_clk_adv)

    dut.i_a_left.value = pack_signed_lanes(activations, DW)
    dut.i_psum_top.value = pack_signed_lanes(biases, ACC_W)

    for _ in range(2 * N + 2):
        await pulse_clock(dut.i_clk_adv)

    expected = reference(activations, weights, biases)
    actual = unpack_signed_lanes(dut.o_c_bottom, N, ACC_W)
    assert actual == expected, f"Expected: {expected}\nActual:   {actual}"

    dut._log.info("Array matrix-vector test passed; seed=%d", SEED)
