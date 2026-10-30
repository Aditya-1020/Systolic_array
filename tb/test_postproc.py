import random
import cocotb
from cocotb.triggers import Timer
from generic import read_signed, write_signed

MAX_EXHAUSTIVE = 1 << 21
MAX_ERRORS = 20

def golden(x: int, m: int, s: int, relu_en: int, out_w: int) -> int:
    prod = x * m
    rnd = (prod + ((1 << s) >> 1)) >> s
    if relu_en:
        rnd = max(rnd, 0)
    return min(max(rnd, -(1 << (out_w - 1))), (1 << (out_w - 1)) - 1)

def get_widths(dut):
    acc_w = len(dut.i_data)
    mult_w = len(dut.i_mult)
    shift_w = len(dut.i_shift)
    out_w = len(dut.o_data)
    return acc_w, mult_w, shift_w, out_w

async def apply_and_check(dut, x, m, s, relu_en, widths, errors):
    acc_w, mult_w, shift_w, out_w = widths
    write_signed(dut.i_data, x, acc_w)
    write_signed(dut.i_mult, m, mult_w)
    dut.i_shift.value = s
    dut.i_relu_en.value = relu_en
    await Timer(1, unit="ns")
    got = read_signed(dut.o_data)
    exp = golden(x, m, s, relu_en, out_w)
    if got != exp:
        errors.append(f"x={x} m={m} s={s} relu={relu_en} got={got} exp={exp}")
        return False
    return True

def report(dut, name, count, errors):
    for line in errors[:MAX_ERRORS]:
        dut._log.error("MISMATCH " + line)
    dut._log.info(f"{name}: {count} vectors, {len(errors)} mismatches")
    assert not errors, f"{name}: {len(errors)} mismatches (first: {errors[0]})"

@cocotb.test()
async def test_postproc_exhaustive(dut):
    widths = get_widths(dut)
    acc_w, mult_w, shift_w, out_w = widths
    space = 1 << (acc_w + mult_w + shift_w + 1)
    assert space <= MAX_EXHAUSTIVE, (
        f"{space} vectors is too many for an exhaustive run "
        f"(ACC_W={acc_w} MULT_W={mult_w} SHIFT_W={shift_w}); "
        f"build with small widths, e.g. -GACC_W=8 -GMULT_W=4 -GOUT_W=4"
    )
    errors = []
    count = 0
    x_range = range(-(1 << (acc_w - 1)), 1 << (acc_w - 1))
    m_range = range(-(1 << (mult_w - 1)), 1 << (mult_w - 1))

    for relu_en in (0, 1):
        for s in range(1 << shift_w):
            for m in m_range:
                for x in x_range:
                    await apply_and_check(dut, x, m, s, relu_en, widths, errors)
                    count += 1
                    if len(errors) >= MAX_ERRORS:
                        report(dut, "exhaustive", count, errors)
    assert count == space
    report(dut, "exhaustive", count, errors)

@cocotb.test()
async def test_postproc_corners_random(dut):
    widths = get_widths(dut)
    acc_w, mult_w, shift_w, out_w = widths
    rng = random.Random(0xC0FFEE)

    def edge_values(w):
        lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
        return sorted({lo, lo + 1, -2, -1, 0, 1, 2, hi - 1, hi})
    errors = []
    count = 0
    for relu_en in (0, 1):
        for s in range(1 << shift_w):
            for m in edge_values(mult_w):
                for x in edge_values(acc_w):
                    await apply_and_check(dut, x, m, s, relu_en, widths, errors)
                    count += 1
    for _ in range(20000):
        x = rng.randint(-(1 << (acc_w - 1)), (1 << (acc_w - 1)) - 1)
        m = rng.randint(-(1 << (mult_w - 1)), (1 << (mult_w - 1)) - 1)
        s = rng.randrange(1 << shift_w)
        relu_en = rng.randrange(2)
        await apply_and_check(dut, x, m, s, relu_en, widths, errors)
        count += 1
    report(dut, "corners_random", count, errors)