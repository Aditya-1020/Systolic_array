import random
import cocotb
from cocotb.triggers import Timer
from helper.generic import pulse_clock, pack_lanes, unpack_lanes, wrap_signed

N = 8
DW = 8
ACC_W = 19
SEED = 0x5A771C


@cocotb.test()
async def test_systolic_array_single_vector_gemm(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    dut.i_w_load.value = 0
    dut.i_w_data.value = 0
    dut.i_a_advance.value = 0
    dut.i_a_valid.value = 0
    dut.i_a_data.value = 0

    await pulse_clock(dut.i_clk)
    await pulse_clock(dut.i_clk)
    dut.i_rstn.value = 1
    await pulse_clock(dut.i_clk)

    rng = random.Random(SEED)
    weights = [[rng.randint(-8, 8) for _ in range(N)] for _ in range(N)]
    activations = [rng.randint(-8, 8) for _ in range(N)]

    # Stream rows in order. After N weight-clock pulses, PE row r contains W[r].
    for row in range(N):
        dut.i_w_data.value = pack_lanes(weights[row], DW)
        dut.i_w_load.value = 1
        await pulse_clock(dut.i_clk)
    dut.i_w_load.value = 0
    dut.i_w_data.value = 0

    lat = 6 * N - 3
    for cycle in range(lat):
        dut.i_a_advance.value = 1
        dut.i_a_data.value = pack_lanes(activations, DW) if cycle == 0 else 0
        dut.i_a_valid.value = 1 if cycle == 0 else 0
        await pulse_clock(dut.i_clk)

    dut.i_a_advance.value = 0
    dut.i_a_valid.value = 0
    dut.i_a_data.value = 0
    await Timer(1, unit="ns")

    assert int(dut.o_c_valid.value) == 1, f"valid did not emerge after {lat} advances"
    expected = [
        wrap_signed(sum(activations[r] * weights[r][c] for r in range(N)), ACC_W)
        for c in range(N)
    ]
    actual = unpack_lanes(dut.o_c_data, N, ACC_W)
    assert actual == expected, f"expected {expected}, got {actual}"
