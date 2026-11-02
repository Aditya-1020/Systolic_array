import random

import cocotb
from cocotb.triggers import Timer

from helper.generic import pack_signed_lanes, pulse_clock, unpack_signed_lanes, wrap_signed

N = 8
DW = 8
OUT_W = 32
Q_W = 8
BIAS_W = 16
MEM_DW = N * DW
BEAT_MASK = (1 << MEM_DW) - 1
BB = (N * BIAS_W) // MEM_DW
ACC_W = 2 * DW + 3
LAT = 2 * N + 1
PP_LAT = 3
LAT_PP = LAT + PP_LAT


def make_case(seed, lo=-128, hi=127):
    rng = random.Random(seed)
    weights = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(N)]
    biases = [rng.randint(-1000, 1000) for _ in range(N)]
    return weights, biases


def rand_vec(rng, lo=-128, hi=127):
    return [rng.randint(lo, hi) for _ in range(N)]


def clamp(value, width):
    return min(max(value, -(1 << (width - 1))), (1 << (width - 1)) - 1)


def expected_output(activation, weights, biases):
    return [wrap_signed(biases[col] + sum(activation[row] * weights[row][col] for row in range(N)), ACC_W) for col in range(N)]


def expected_quant(activation, weights, biases, mult, shift, relu):
    lanes = []
    for acc in expected_output(activation, weights, biases):
        value = max(acc, 0) if relu else acc
        lanes.append(clamp((value * mult + ((1 << shift) >> 1)) >> shift, Q_W))
    return lanes


async def cycle(dut):
    await Timer(1, unit="ns")
    snapshot = {
        "vld": int(dut.o_c_vld.value),
        "last": int(dut.o_c_last.value),
        "data": int(dut.o_c_data.value),
    }
    await pulse_clock(dut.i_clk)
    return snapshot


async def reset_dut(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0

    dut.i_relu_en.value = 0
    dut.i_quant_en.value = 0
    dut.i_mult.value = 1
    dut.i_shift.value = 0

    dut.i_wdata.value = 0
    dut.i_bias_shift.value = 0
    dut.i_w_shift.value = 0

    dut.i_a_data.value = 0
    dut.i_a_vld.value = 0
    dut.i_a_last.value = 0
    dut.i_flush.value = 0

    for _ in range(3):
        await pulse_clock(dut.i_clk)

    dut.i_rstn.value = 1
    await cycle(dut)


def set_config(dut, quant=0, relu=0, mult=1, shift=0):
    dut.i_quant_en.value = quant
    dut.i_relu_en.value = relu
    dut.i_mult.value = mult
    dut.i_shift.value = shift


async def load_bias(dut, biases):
    flat = pack_signed_lanes(biases, BIAS_W)
    for beat in range(BB):
        dut.i_wdata.value = (flat >> (beat * MEM_DW)) & BEAT_MASK
        dut.i_bias_shift.value = 1
        await cycle(dut)
    dut.i_bias_shift.value = 0
    dut.i_wdata.value = 0


async def load_weights(dut, weights):
    for row in weights:
        dut.i_wdata.value = pack_signed_lanes(row, DW)
        dut.i_w_shift.value = 1
        await cycle(dut)
    dut.i_w_shift.value = 0
    dut.i_wdata.value = 0


async def prepare(dut, seed, quant=0, relu=0, mult=1, shift=0, lo=-128, hi=127):
    weights, biases = make_case(seed, lo, hi)
    await reset_dut(dut)
    set_config(dut, quant, relu, mult, shift)
    await load_bias(dut, biases)
    await load_weights(dut, weights)
    return weights, biases


async def run_stream(dut, items, weights, biases, quant=0, relu=0, mult=1, shift=0, flush_at=None, seed=0):
    """items: one entry per cycle, either None (idle) or (activation, last).

    Idle cycles carry random garbage on i_a_data/i_a_last with i_a_vld=0.
    Every item presented at cycle i must come out at cycle i + latency, and no
    other cycle may show a valid output. Items presented at or before flush_at
    are dropped by the flush.
    """
    rng = random.Random(seed)
    latency = LAT_PP if quant else LAT
    expected = {}
    for index, item in enumerate(items):
        if item is None or (flush_at is not None and index <= flush_at):
            continue
        activation, last = item
        if quant:
            lanes = expected_quant(activation, weights, biases, mult, shift, relu)
        else:
            lanes = expected_output(activation, weights, biases)
        expected[index + latency] = (lanes, last)

    # drain the whole sideband (LAT_PP) so a following run in the other mode starts clean
    for index in range(len(items) + LAT_PP + 2):
        item = items[index] if index < len(items) else None
        if item is None:
            dut.i_a_vld.value = 0
            dut.i_a_last.value = rng.randint(0, 1)
            dut.i_a_data.value = rng.getrandbits(N * DW)
        else:
            activation, last = item
            dut.i_a_vld.value = 1
            dut.i_a_last.value = int(last)
            dut.i_a_data.value = pack_signed_lanes(activation, DW)
        dut.i_flush.value = int(index == flush_at)

        snapshot = await cycle(dut)

        if index in expected:
            lanes, last = expected[index]
            assert snapshot["vld"] == 1, f"Cycle {index}: expected valid output"
            actual = unpack_signed_lanes(snapshot["data"], N, OUT_W)
            assert actual == lanes, f"Cycle {index}: expected {lanes}, got {actual}"
            assert snapshot["last"] == int(last), f"Cycle {index}: expected last={int(last)}, got {snapshot['last']}"
        else:
            assert snapshot["vld"] == 0, f"Cycle {index}: unexpected valid output"

    dut.i_a_vld.value = 0
    dut.i_a_last.value = 0
    dut.i_flush.value = 0


@cocotb.test()
async def test_single_vector_latency_and_value(dut):
    weights, biases = await prepare(dut, 101)
    activation = [3, -2, 7, -8, 0, 127, -128, 11]
    await run_stream(dut, [(activation, True)], weights, biases)


@cocotb.test()
async def test_requant_latency_and_value(dut):
    mult, shift = 100, 9
    weights, biases = await prepare(dut, 202, quant=1, relu=1, mult=mult, shift=shift, lo=-8, hi=8)
    rng = random.Random(202)
    items = [(rand_vec(rng, -8, 8), index == 9) for index in range(10)]
    await run_stream(dut, items, weights, biases, quant=1, relu=1, mult=mult, shift=shift)


@cocotb.test()
async def test_requant_saturation(dut):
    mult, shift = 0x7FFF, 8
    weights, biases = await prepare(dut, 303, quant=1, relu=0, mult=mult, shift=shift)
    rng = random.Random(303)
    items = [(rand_vec(rng), index == 19) for index in range(20)]
    lanes = [expected_quant(a, weights, biases, mult, shift, 0) for a, _ in items]
    assert any(v in (-128, 127) for row in lanes for v in row), "case does not exercise saturation"
    await run_stream(dut, items, weights, biases, quant=1, relu=0, mult=mult, shift=shift)


@cocotb.test()
async def test_back_to_back_vectors(dut):
    weights, biases = await prepare(dut, 404)
    rng = random.Random(404)
    count = 2 * LAT + 3
    items = [(rand_vec(rng), index == count - 1) for index in range(count)]
    await run_stream(dut, items, weights, biases)


@cocotb.test()
async def test_bubbles_and_garbage_do_not_corrupt(dut):
    weights, biases = await prepare(dut, 505)
    rng = random.Random(505)
    items = []
    for _ in range(80):
        if rng.random() < 0.5:
            items.append((rand_vec(rng), rng.random() < 0.2))
        else:
            items.append(None)
    await run_stream(dut, items, weights, biases, seed=506)


@cocotb.test()
async def test_flush_drops_in_flight_rows(dut):
    weights, biases = await prepare(dut, 606)
    rng = random.Random(606)
    items = [(rand_vec(rng), index == 11) for index in range(12)]
    # rows 0..5 (including the one presented in the flush cycle) must vanish,
    # rows 6..11 behind the flush come out at their normal latency
    await run_stream(dut, items, weights, biases, flush_at=5)


@cocotb.test()
async def test_weight_and_bias_reload(dut):
    weights, biases = await prepare(dut, 707)
    rng = random.Random(707)
    items = [(rand_vec(rng), index == 4) for index in range(5)]
    await run_stream(dut, items, weights, biases)

    new_weights, new_biases = make_case(708)
    await load_bias(dut, new_biases)
    await load_weights(dut, new_weights)
    items = [(rand_vec(rng), index == 4) for index in range(5)]
    await run_stream(dut, items, new_weights, new_biases)


@cocotb.test()
async def test_bias_extremes_do_not_overflow(dut):
    await reset_dut(dut)
    weights = [[-128] * N for _ in range(N)]
    biases = [32767, -32768, 32767, -32768, 0, 1, -1, 12345]
    await load_bias(dut, biases)
    await load_weights(dut, weights)

    items = [
        ([-128] * N, False),  # largest positive sum + bias
        ([127] * N, False),   # largest negative sum + bias
        ([0] * N, False),
        ([-128, 127] * (N // 2), True),
    ]
    for activation, _ in items:
        assert all(abs(v) < (1 << (ACC_W - 1)) for v in expected_output(activation, weights, biases))
    await run_stream(dut, items, weights, biases)


@cocotb.test()
async def test_mode_switch_raw_to_requant(dut):
    mult, shift = 37, 6
    weights, biases = await prepare(dut, 808, lo=-8, hi=8)
    rng = random.Random(808)
    items = [(rand_vec(rng, -8, 8), index == 5) for index in range(6)]
    await run_stream(dut, items, weights, biases)

    set_config(dut, quant=1, relu=1, mult=mult, shift=shift)
    items = [(rand_vec(rng, -8, 8), index == 5) for index in range(6)]
    await run_stream(dut, items, weights, biases, quant=1, relu=1, mult=mult, shift=shift)

    set_config(dut, quant=0)
    items = [(rand_vec(rng, -8, 8), index == 5) for index in range(6)]
    await run_stream(dut, items, weights, biases)