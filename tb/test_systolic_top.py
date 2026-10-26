import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from golden_model import dot_outputs, pack_bytes, unpack_signed_bytes

N = 8
ACC_W = 24
CLOCK_NS = 10
TIMEOUT = 2000


async def tick(dut, cycles=1):
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")


async def wait_for(dut, signal, expected, label, limit=TIMEOUT):
    for _ in range(limit):
        if int(signal.value) == expected:
            return
        await tick(dut)
    raise AssertionError(
        f"timeout waiting for {label}={expected}; got {int(signal.value)}"
    )


async def wait_for_bit(dut, signal, bit, expected, label, limit=TIMEOUT):
    mask = 1 << bit
    for _ in range(limit):
        if bool(int(signal.value) & mask) == bool(expected):
            return
        await tick(dut)
    raise AssertionError(
        f"timeout waiting for {label} bit {bit}={expected}; "
        f"got 0b{int(signal.value):b}"
    )


async def write_word(dut, address, data):
    await FallingEdge(dut.i_clk)
    dut.i_host_w_addr.value = address
    dut.i_host_w_data.value = data
    dut.i_host_w_en.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_host_w_en.value = 0


async def pulse(dut, signal):
    await FallingEdge(dut.i_clk)
    signal.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.i_clk)
    signal.value = 0


async def read_word(dut, address):
    await FallingEdge(dut.i_clk)
    dut.i_host_r_addr.value = address
    dut.i_host_r_en.value = 1
    for _ in range(8):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.o_host_r_valid.value):
            data = int(dut.o_host_r_data.value)
            await FallingEdge(dut.i_clk)
            dut.i_host_r_en.value = 0
            return data
    dut.i_host_r_en.value = 0
    raise AssertionError(f"timeout reading result address {address}")


@cocotb.test()
async def top_level_matrix_vector_test(dut):
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())

    inputs = {
        "i_rstn": 0,
        "i_host_w_en": 0,
        "i_host_w_addr": 0,
        "i_host_w_data": 0,
        "i_act_push": 0,
        "i_act_push_half": 0,
        "i_host_r_en": 0,
        "i_host_r_addr": 0,
        "i_res_pop": 0,
        "i_res_pop_half": 0,
        "i_cmd_load_w": 0,
        "i_cmd_start": 0,
        "i_w_base": 0,
        "i_a_base": 0,
        "i_count": 1,
        "i_shift": 1,
        "i_relu_en": 0,
        "i_bias": 0,
    }
    for name, value in inputs.items():
        getattr(dut, name).value = value

    # Reset, then allow the top-level two-flop reset synchronizer to release.
    await tick(dut, 5)
    await FallingEdge(dut.i_clk)
    dut.i_rstn.value = 1
    await tick(dut, 5)
    await wait_for(dut, dut.o_cmd_ready, 1, "command ready")

    weights_by_row = [
        [((row * 3 + col * 2 + 1) % 7) - 3 for col in range(N)]
        for row in range(N)
    ]
    for row, weights in enumerate(weights_by_row):
        await write_word(dut, row, pack_bytes(weights))

    dut.i_act_push_half.value = 0
    await pulse(dut, dut.i_act_push)
    await wait_for_bit(dut, dut.o_act_full, 0, 1, "weight source bank full")

    await FallingEdge(dut.i_clk)
    dut.i_w_base.value = 0
    dut.i_cmd_load_w.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.i_clk)
    dut.i_cmd_load_w.value = 0

    await wait_for(dut, dut.o_weights_loaded, 1, "weights loaded")
    await wait_for(dut, dut.o_cmd_ready, 1, "weight feeder drained")
    await wait_for_bit(dut, dut.o_act_full, 0, 0, "weight source bank released")

    activations = [
        [-4, 3, -2, 1, 5, -3, 2, 4],
        [2, -5, 4, -1, 3, 0, -2, 5],
        [1, 2, 3, 4, -1, -2, -3, -4],
        [-128, 127, -64, 63, -32, 31, -16, 15],
    ]
    for address, vector in enumerate(activations):
        await write_word(dut, address, pack_bytes(vector))

    dut.i_act_push_half.value = 0
    await pulse(dut, dut.i_act_push)
    await wait_for_bit(dut, dut.o_act_full, 0, 1, "activation bank full")
    await wait_for(dut, dut.o_cmd_ready, 1, "command ready before start")

    dut.i_count.value = len(activations)
    dut.i_a_base.value = 0
    dut.i_shift.value = 1
    dut.i_relu_en.value = 0
    dut.i_bias.value = 0

    await FallingEdge(dut.i_clk)
    dut.i_cmd_start.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.i_clk)
    dut.i_cmd_start.value = 0

    await wait_for_bit(dut, dut.o_res_full, 0, 1, "result bank full")

    weights_by_output = [
        [weights_by_row[row][col] for row in range(N)] for col in range(N)
    ]
    for address, vector in enumerate(activations):
        packed = await read_word(dut, address)
        got = unpack_signed_bytes(packed, N)
        expected = dot_outputs(
            vector,
            weights_by_output,
            biases=[0] * N,
            shift=1,
            relu=False,
            acc_width=ACC_W,
        )
        assert got == expected, (
            f"result word {address}: got {got}, expected {expected}; "
            f"activation={vector}"
        )

    dut.i_res_pop_half.value = 0
    await pulse(dut, dut.i_res_pop)
    await wait_for_bit(dut, dut.o_res_full, 0, 0, "result bank released")
