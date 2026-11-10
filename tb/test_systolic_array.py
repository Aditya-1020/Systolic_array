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
    dut.i_clear.value = 0

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

    pe_lat = 7
    lat = pe_lat * (2 * N - 1)
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


async def reset_array(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    dut.i_w_load.value = 0
    dut.i_w_data.value = 0
    dut.i_a_advance.value = 0
    dut.i_a_valid.value = 0
    dut.i_a_data.value = 0
    dut.i_clear.value = 0
    await pulse_clock(dut.i_clk)
    await pulse_clock(dut.i_clk)
    dut.i_rstn.value = 1
    await pulse_clock(dut.i_clk)


async def advance(dut, valid=0, data=0, count=1):
    for _ in range(count):
        dut.i_a_advance.value = 1
        dut.i_a_valid.value = valid
        dut.i_a_data.value = data
        await pulse_clock(dut.i_clk)
    dut.i_a_advance.value = 0
    dut.i_a_valid.value = 0
    dut.i_a_data.value = 0


@cocotb.test()
async def test_valid_pipeline_bubbles_stalls_and_back_to_back(dut):
    await reset_array(dut)
    latency = 7 * (2 * N - 1)

    await advance(dut, valid=1, data=pack_lanes([1] * N, DW))
    for _ in range(5):
        dut.i_a_advance.value = 0
        await pulse_clock(dut.i_clk)
        assert int(dut.o_c_valid.value) == 0, "valid must not advance during a stall"

    await advance(dut, count=latency - 1)
    assert int(dut.o_c_valid.value) == 1, "first token did not emerge after exactly VALID_LAT advances"

    for _ in range(3):
        dut.i_a_advance.value = 0
        await pulse_clock(dut.i_clk)
        assert int(dut.o_c_valid.value) == 1, "output valid must hold while advance is stalled"

    await advance(dut, valid=1, data=pack_lanes([2] * N, DW))
    assert int(dut.o_c_valid.value) == 0, "first token should leave as second token enters"
    await advance(dut, count=latency - 1)
    assert int(dut.o_c_valid.value) == 1, "second token did not emerge at the expected enabled-cycle latency"
    await advance(dut)
    assert int(dut.o_c_valid.value) == 0, "valid pipeline failed to drain"

@cocotb.test()
async def test_clear_flushes_valid_without_advance(dut):
    await reset_array(dut)
    latency = 7 * (2 * N - 1)
    await advance(dut, valid=1, data=pack_lanes([3] * N, DW), count=12)
    dut.i_a_advance.value = 0
    dut.i_clear.value = 1
    await pulse_clock(dut.i_clk)
    dut.i_clear.value = 0
    for _ in range(3):
        await pulse_clock(dut.i_clk)
        assert int(dut.o_c_valid.value) == 0, "clear must flush valid state with array clock gated"
    await advance(dut, count=latency - 1)
    assert int(dut.o_c_valid.value) == 0, "pre-clear token leaked through valid pipeline"


@cocotb.test()
async def test_valid_latency_counts_enabled_advances(dut):
    await reset_array(dut)
    latency = 7 * (2 * N - 1)
    await advance(dut, valid=1, data=pack_lanes([-1] * N, DW))
    for _ in range(10):
        dut.i_a_advance.value = 0
        await pulse_clock(dut.i_clk)
        assert int(dut.o_c_valid.value) == 0, "valid advanced while i_a_advance was low"
    await advance(dut, count=latency - 1)
    assert int(dut.o_c_valid.value) == 1, "latency must be measured in enabled advances"
