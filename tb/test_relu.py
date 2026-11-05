import random
import cocotb
from cocotb.triggers import Timer
from helper.generic import pack_lanes, unpack_lanes

N = 8
DW = 8
ACC_W = 19
SEED = 0xAE10


def golden_relu_sat(x, relu_en):
    if relu_en and x < 0:
        return 0
    return min(127, max(-128, x))


@cocotb.test()
async def test_relu_saturate_all_lanes(dut):
    rng = random.Random(SEED)
    values = [-(1 << 18), -1000, -129, -128, -127, -1,
              0, 1, 126, 127, 128, 1000, (1 << 18) - 1]
    values += [rng.randint(-(1 << 18), (1 << 18) - 1) for _ in range(256)]

    for relu_en in (0, 1):
        for base in range(0, len(values), N):
            lanes = (values[base:base + N] + [0] * N)[:N]
            dut.i_data.value = pack_lanes(lanes, ACC_W)
            dut.i_relu_en.value = relu_en
            await Timer(1, unit="ns")
            actual = unpack_lanes(dut.o_data, N, DW)
            expected = [golden_relu_sat(x, relu_en) for x in lanes]
            assert actual == expected, (
                f"relu_en={relu_en}, input={lanes}, expected={expected}, got={actual}"
            )
