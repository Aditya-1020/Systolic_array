import random
import cocotb
from helper.generic import pulse_clock, read_signed, wrap_signed, write_signed

DW = 8
ACC_W = 19
SEED = 0x5045


@cocotb.test()
async def test_pe_registered_weight_and_mac(dut):
    dut.i_clk_w.value = 0
    dut.i_clk_adv.value = 0
    dut.i_w.value = 0
    dut.i_a.value = 0
    dut.i_psum.value = 0

    rng = random.Random(SEED)
    vectors = [
        (-128, -128, 0),
        (-128, 127, 1),
        (127, 127, -1),
        (127, -128, 100),
        (0, 0, 0),
        (-1, -1, -1),
        (1, -1, 1),
    ]
    vectors += [
        (rng.randint(-128, 127), rng.randint(-128, 127),
         rng.randint(-(1 << (ACC_W-1)), (1 << (ACC_W-1))-1))
        for _ in range(256)
    ]

    for index, (weight, activation, psum) in enumerate(vectors):
        write_signed(dut.i_w, weight, DW)
        await pulse_clock(dut.i_clk_w)
        assert read_signed(dut.o_w) == weight, f"vector {index}: registered weight"

        write_signed(dut.i_a, activation, DW)
        write_signed(dut.i_psum, psum, ACC_W)
        await pulse_clock(dut.i_clk_adv)

        assert read_signed(dut.o_a) == activation, f"vector {index}: activation register"
        expected = wrap_signed(psum + activation * weight, ACC_W)
        actual = read_signed(dut.o_psum)
        assert actual == expected, f"vector {index}: expected psum {expected}, got {actual}"
