import random
import cocotb
from helper.generic import pulse_clock, read_signed, write_signed, wrap_signed

DW = 8
ACC_W = 24
NUM_RANDOM_VECTORS = 100
SEED = 42

async def write_weight(dut, weight):
    write_signed(dut.i_w, weight, DW)
    await pulse_clock(dut.i_clk_w)

async def advance_pe(dut, activation, psum):
    write_signed(dut.i_a, activation, DW)
    write_signed(dut.i_psum, psum, ACC_W)
    await pulse_clock(dut.i_clk_adv)

def generate_vectors(count=NUM_RANDOM_VECTORS, seed=SEED):
    rng = random.Random(seed)
    vectors = [
        (-128, -128, 0),
        (-128, 127, 1),
        (127, 127, -1),
        (127, -128, 100),
        (0, 0, 0),
        (-1, -1, -1),
        (1, -1, 1),
    ]
    vectors.extend((rng.randint(-128, 127), rng.randint(-128, 127), rng.randint(-(1 << (ACC_W - 1)), (1 << (ACC_W - 1)) - 1),) for _ in range(count))
    return vectors

@cocotb.test()
async def test_pe_against_golden(dut):
    dut.i_clk_w.value = 0
    dut.i_clk_adv.value = 0
    dut.i_w.value = 0
    dut.i_a.value = 0
    dut.i_psum.value = 0

    initial_weight = 2
    initial_activation = 3

    await write_weight(dut, initial_weight)
    assert read_signed(dut.o_w) == initial_weight
    await advance_pe(dut, initial_activation, 0)
    assert read_signed(dut.o_a) == initial_activation
    expected_prod = wrap_signed(initial_activation * initial_weight, 2 * DW)

    vectors = generate_vectors()

    for index, (weight, activation, psum) in enumerate(vectors):
        await write_weight(dut, weight)

        actual_w = read_signed(dut.o_w)
        assert actual_w == weight, (f"Vector {index}: o_w expected {weight}, got {actual_w}")

        expected_psum = wrap_signed(psum + expected_prod, ACC_W)
        next_prod = wrap_signed(activation * weight, 2 * DW)

        await advance_pe(dut, activation, psum)

        actual_a = read_signed(dut.o_a)
        actual_psum = read_signed(dut.o_psum)

        assert actual_a == activation, (f"Vector {index}: o_a expected {activation}, got {actual_a}")
        assert actual_psum == expected_psum, (f"Vector {index}: o_psum expected {expected_psum}, " f"got {actual_psum}")
        expected_prod = next_prod
    dut._log.info("PE test passed: %d vectors, seed=%d", len(vectors), SEED,)