import itertools
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge
from generic import read_signed, write_signed

LAT = 3
MAX_EXHAUSTIVE = 1 << 21
MAX_ERRORS = 20

def golden(x: int, m: int, s: int, relu_en: int, out_w: int) -> int:
    prod = x * m
    rnd = (prod + ((1 << s) >> 1)) >> s
    if relu_en:
        rnd = max(rnd, 0)
    return min(max(rnd, -(1 << (out_w - 1))), (1 << (out_w - 1)) - 1)

def get_widths(dut):
    return len(dut.i_data), len(dut.i_mult), len(dut.i_shift), len(dut.o_data)

async def reset_dut(dut, widths):
    acc_w, mult_w, shift_w, out_w = widths
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rstn.value = 0
    dut.i_en.value = 1
    dut.i_valid.value = 0
    dut.i_data.value = 0
    dut.i_mult.value = 0
    dut.i_shift.value = 0
    dut.i_relu_en.value = 0
    for _ in range(3):
        await FallingEdge(dut.i_clk)
    dut.i_rstn.value = 1

async def run_plan(dut, plan, widths, errors):
    acc_w, mult_w, shift_w, out_w = widths
    pipe = [None] * LAT
    flush = [((0, 0, 0, 0), 0, 1, 1)] * LAT
    count = 0

    for (x, m, s, relu_en), valid, en, rstn in itertools.chain(plan, flush):
        await FallingEdge(dut.i_clk)

        got_valid = int(dut.o_valid.value)
        exp = pipe[LAT - 1]
        if exp is None:
            if got_valid:
                errors.append(f"cycle {count}: o_valid=1 on a bubble")
        elif not got_valid:
            errors.append(f"cycle {count}: o_valid=0, expected {exp}")
        else:
            got = read_signed(dut.o_data)
            if got != exp:
                errors.append(f"cycle {count}: got={got} exp={exp}")

        write_signed(dut.i_data, x, acc_w)
        write_signed(dut.i_mult, m, mult_w)
        dut.i_shift.value = s
        dut.i_relu_en.value = relu_en
        dut.i_valid.value = valid
        dut.i_en.value = en
        dut.i_rstn.value = rstn

        if not rstn:
            pipe = [None] * LAT
        elif en:
            new = golden(x, m, s, relu_en, out_w) if valid else None
            pipe = [new] + pipe[:-1]

        count += 1
        if len(errors) >= MAX_ERRORS:
            break
    return count

def report(dut, name, count, errors):
    for line in errors[:MAX_ERRORS]:
        dut._log.error("MISMATCH " + line)
    dut._log.info(f"{name}: {count} cycles, {len(errors)} mismatches")
    assert not errors, f"{name}: {len(errors)} mismatches (first: {errors[0]})"

def edge_values(w):
    lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
    return sorted({lo, lo + 1, -2, -1, 0, 1, 2, hi - 1, hi})

def rand_vec(rng, widths):
    acc_w, mult_w, shift_w, _ = widths
    return (
        rng.randint(-(1 << (acc_w - 1)), (1 << (acc_w - 1)) - 1),
        rng.randint(-(1 << (mult_w - 1)), (1 << (mult_w - 1)) - 1),
        rng.randrange(1 << shift_w),
        rng.randrange(2),
    )

@cocotb.test()
async def test_postproc_corners_random(dut):
    widths = get_widths(dut)
    acc_w, mult_w, shift_w, _ = widths
    rng = random.Random(0xC0FFEE)
    await reset_dut(dut, widths)

    def plan():
        for relu_en in (0, 1):
            for s in range(1 << shift_w):
                for m in edge_values(mult_w):
                    for x in edge_values(acc_w):
                        yield (x, m, s, relu_en), 1, 1, 1
        for _ in range(20000):
            yield rand_vec(rng, widths), 1, 1, 1

    errors = []
    count = await run_plan(dut, plan(), widths, errors)
    report(dut, "corners_random", count, errors)


@cocotb.test()
async def test_postproc_stall_bubbles(dut):
    widths = get_widths(dut)
    rng = random.Random(0xBEEF)
    await reset_dut(dut, widths)

    def plan():
        for _ in range(30000):
            yield rand_vec(rng, widths), int(rng.random() < 0.7), int(rng.random() < 0.6), 1

    errors = []
    count = await run_plan(dut, plan(), widths, errors)
    report(dut, "stall_bubbles", count, errors)


@cocotb.test()
async def test_postproc_reset_mid_stream(dut):
    # reset clears in-flight valids even while the pipe is full
    widths = get_widths(dut)
    rng = random.Random(0xFACE)
    await reset_dut(dut, widths)

    def plan():
        for _ in range(5000):
            yield rand_vec(rng, widths), 1, int(rng.random() < 0.8), int(rng.random() < 0.9)

    errors = []
    count = await run_plan(dut, plan(), widths, errors)
    report(dut, "reset_mid_stream", count, errors)