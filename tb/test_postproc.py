import random

import cocotb
from cocotb.triggers import Timer

from generic import pulse_clock, read_signed, write_signed

LAT = 3
MAX_ERRORS = 20


def clamp(v: int, w: int) -> int:
    return min(max(v, -(1 << (w - 1))), (1 << (w - 1)) - 1)


def bypass(x: int, relu_en: int) -> int:
    return max(x, 0) if relu_en else x


def round_shift(prod: int, s: int) -> int:
    return (prod + ((1 << s) >> 1)) >> s


def stage1(x: int, m: int, relu_en: int, quant_en: int) -> int:
    # operands are isolated to 0 when quant_en=0 at capture time
    v = bypass(x, relu_en) if quant_en else 0
    return v * m


def get_widths(dut):
    # (acc_w, mult_bits = MULT_W-1, shift_w, out_w)
    return len(dut.i_data), len(dut.i_mult), len(dut.i_shift), len(dut.o_data)


async def tick(dut, en):
    # en=0 emulates a gated clock: time passes, no edge
    if en:
        await pulse_clock(dut.i_clk)
    else:
        await Timer(3, unit="ns")


async def init_dut(dut):
    dut.i_clk.value = 0
    dut.i_relu_en.value = 0
    dut.i_quant_en.value = 0
    dut.i_data.value = 0
    dut.i_mult.value = 0
    dut.i_shift.value = 0
    await Timer(1, unit="ns")


async def probe_q_w(dut, widths):
    # Q_W is not visible on a port: push both extremes through the quant path
    acc_w, mult_bits, shift_w, out_w = widths
    mmax = (1 << mult_bits) - 1
    dut.i_relu_en.value = 0
    dut.i_quant_en.value = 1
    dut.i_shift.value = 0
    dut.i_mult.value = mmax
    res = []
    for x in ((1 << (acc_w - 1)) - 1, -(1 << (acc_w - 1))):
        write_signed(dut.i_data, x, acc_w)
        for _ in range(LAT):
            await pulse_clock(dut.i_clk)
        res.append((x * mmax, read_signed(dut.o_data)))
    (pos_prod, pos_out), (neg_prod, neg_out) = res
    if pos_out != pos_prod:
        return pos_out.bit_length() + 1      # 2**(q-1) - 1
    if neg_out != neg_prod:
        return (-neg_out).bit_length()       # -2**(q-1)
    return out_w                             # never clamps


async def run_plan(dut, plan, widths, q_w, errors):
    """plan: iterable of (x, m, s, relu_en, quant_en, en), one entry per cycle.

    quant_en=0 outputs are combinational (checked every cycle). quant_en=1
    outputs come from the 3 stage registers; pipe = [prod_q, rounded_q, sat_q]
    (None = unknown), updated only when en=1. i_shift is not registered: the
    round stage uses the value live at the capturing edge.
    """
    acc_w, mult_bits, shift_w, out_w = widths
    pipe = [None] * LAT
    count = 0

    for x, m, s, relu_en, quant_en, en in plan:
        write_signed(dut.i_data, x, acc_w)
        dut.i_mult.value = m
        dut.i_shift.value = s
        dut.i_relu_en.value = relu_en
        dut.i_quant_en.value = quant_en
        await tick(dut, en)

        if en:
            pipe = [
                stage1(x, m, relu_en, quant_en),
                None if pipe[0] is None else round_shift(pipe[0], s),
                None if pipe[1] is None else clamp(pipe[1], q_w),
            ]

        exp = pipe[LAT - 1] if quant_en else bypass(x, relu_en)
        if exp is not None:
            got = read_signed(dut.o_data)
            if got != exp:
                errors.append(
                    f"cycle {count}: x={x} m={m} s={s} relu={relu_en} "
                    f"quant={quant_en} en={en} got={got} exp={exp}"
                )
        count += 1
        if len(errors) >= MAX_ERRORS:
            break
    return count


def report(dut, name, count, errors):
    for line in errors[:MAX_ERRORS]:
        dut._log.error("MISMATCH " + line)
    dut._log.info(f"{name}: {count} cycles, {len(errors)} mismatches")
    assert not errors, f"{name}: {len(errors)} mismatches (first: {errors[0]})"


def edge_values(w, signed=True):
    if signed:
        lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
        return sorted({lo, lo + 1, -2, -1, 0, 1, 2, hi - 1, hi})
    hi = (1 << w) - 1
    return sorted({0, 1, 2, hi // 2, hi - 1, hi})


def rand_cycle(rng, widths, en_prob=1.0):
    acc_w, mult_bits, shift_w, _ = widths
    return (
        rng.randint(-(1 << (acc_w - 1)), (1 << (acc_w - 1)) - 1),
        rng.randrange(1 << mult_bits),
        rng.randrange(1 << shift_w),
        rng.randrange(2),
        rng.randrange(2),
        int(rng.random() < en_prob),
    )

@cocotb.test()
async def test_postproc_corners_random(dut):
    # works at any width, including the production defaults
    widths = get_widths(dut)
    acc_w, mult_bits, shift_w, out_w = widths
    rng = random.Random(0xC0FFEE)
    await init_dut(dut)
    q_w = await probe_q_w(dut, widths)
    dut._log.info(f"probed Q_W={q_w}")

    def plan():
        for relu_en in (0, 1):
            for x in edge_values(acc_w):
                yield x, 0, 0, relu_en, 0, 1
        for relu_en in (0, 1):
            for s in range(1 << shift_w):
                for m in edge_values(mult_bits, signed=False):
                    for x in edge_values(acc_w):
                        yield x, m, s, relu_en, 1, 1
        for _ in range(LAT - 1):
            yield 0, 0, 0, 0, 1, 1
        for _ in range(20000):
            yield rand_cycle(rng, widths)

    errors = []
    count = await run_plan(dut, plan(), widths, q_w, errors)
    report(dut, "corners_random", count, errors)


@cocotb.test()
async def test_postproc_stall_and_mode_flips(dut):
    # random controls every cycle plus random clock stalls; inputs presented
    # during a stall must not be captured
    widths = get_widths(dut)
    rng = random.Random(0xBEEF)
    await init_dut(dut)
    q_w = await probe_q_w(dut, widths)
    dut._log.info(f"probed Q_W={q_w}")

    def plan():
        for _ in range(30000):
            yield rand_cycle(rng, widths, en_prob=0.6)

    errors = []
    count = await run_plan(dut, plan(), widths, q_w, errors)
    report(dut, "stall_and_mode_flips", count, errors)