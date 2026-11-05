import random
import cocotb
from cocotb.triggers import Timer
from helper.generic import pack_lanes, unpack_lanes, wrap_signed

N = 8
ACC_W = 19
SEED = 0xA11CE


def golden_round(x, shift, round_en):
    bias = (1 << (shift - 1)) if (round_en and shift > 0) else 0
    return wrap_signed((x + bias) >> shift, ACC_W)


@cocotb.test()
async def test_round_lane_vectors(dut):
    rng = random.Random(SEED)
    values = [-(1 << 18), -(1 << 18) + 1, -257, -3, -2, -1,
              0, 1, 2, 3, 255, 256, (1 << 18) - 1]
    values += [rng.randint(-(1 << 18), (1 << 18) - 1) for _ in range(256)]

    for shift in range(19):
        for round_en in (0, 1):
            lanes = [values[(k * 13 + shift) % len(values)] for k in range(N)]
            dut.i_data.value = pack_lanes(lanes, ACC_W)
            dut.i_shift.value = shift
            bias = (1 << (shift - 1)) if (round_en and shift > 0) else 0
            dut.i_round_const.value = bias
            await Timer(1, unit="ns")
            actual = unpack_lanes(dut.o_data, N, ACC_W)
            expected = [golden_round(x, shift, round_en) for x in lanes]
            assert actual == expected, (
                f"shift={shift} round_en={round_en}: expected={expected}, got={actual}"
            )
