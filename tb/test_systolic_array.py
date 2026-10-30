from collections import deque
import random
import cocotb
from cocotb.triggers import Timer
from helper.generic import pack_signed_lanes, pulse_clock, unpack_signed_lanes, wrap_signed

N = 8
DW = 8
OUT_W = 32
ACC_W = 2 * DW + 3
LAT = 2 * N + 1
TIMEOUT = 200

async def cycle(dut):
    await Timer(1, unit="ns")
    a_ready = int(dut.s_axis_a_tready.value)
    a_valid = int(dut.s_axis_a_tvalid.value)
    w_ready = int(dut.s_axis_w_tready.value)
    w_valid = int(dut.s_axis_w_tvalid.value)
    m_valid = int(dut.m_axis_c_tvalid.value)
    m_ready = int(dut.m_axis_c_tready.value)

    snapshot = {
        "a_ready": a_ready,
        "a_fire": a_valid and a_ready,
        "w_ready": w_ready,
        "w_fire": w_valid and w_ready,
        "m_valid": m_valid,
        "m_ready": m_ready,
        "m_fire": m_valid and m_ready,
        "m_last": int(dut.m_axis_c_tlast.value) if m_valid else 0,
        "m_data": int(dut.m_axis_c_tdata.value) if m_valid else 0,
    }
    await pulse_clock(dut.i_clk)
    return snapshot


def make_case(seed):
    rng = random.Random(seed)
    weights = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(N)]
    biases = [rng.randint(-1000, 1000) for _ in range(N)]
    return weights, biases


def expected_output(activation, weights, biases):
    return [wrap_signed(biases[col] + sum(activation[row] * weights[row][col] for row in range(N)), ACC_W,) for col in range(N)]

def output_lanes(packed_data):
    return unpack_signed_lanes(packed_data, N, OUT_W)

async def reset_dut(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    dut.i_bias.value = 0
    dut.i_load_w.value = 0
    dut.s_axis_w_tvalid.value = 0
    dut.s_axis_w_tdata.value = 0
    dut.s_axis_a_tvalid.value = 0
    dut.s_axis_a_tdata.value = 0
    dut.s_axis_a_tlast.value = 0
    dut.m_axis_c_tready.value = 1

    for _ in range(3):
        await pulse_clock(dut.i_clk)

    dut.i_rstn.value = 1
    await cycle(dut)

async def send_weight_rows(dut, weights):
    for row in weights:
        dut.s_axis_w_tdata.value = pack_signed_lanes(row, DW)
        dut.s_axis_w_tvalid.value = 1

        for _ in range(TIMEOUT):
            snapshot = await cycle(dut)
            if snapshot["w_fire"]:
                break
        else:
            raise AssertionError("Timed out waiting for weight handshake")
        dut.s_axis_w_tvalid.value = 0
    assert int(dut.o_weights_loaded.value) == 1
    assert int(dut.s_axis_w_tready.value) == 0

async def request_weight_load(dut):
    dut.i_load_w.value = 1
    await cycle(dut)
    dut.i_load_w.value = 0

    for _ in range(TIMEOUT):
        if int(dut.s_axis_w_tready.value):
            return
        await cycle(dut)
    raise AssertionError("Timed out waiting for weight-load state")

async def prepare(dut, seed):
    weights, biases = make_case(seed)
    await reset_dut(dut)
    dut.i_bias.value = pack_signed_lanes(biases, OUT_W)
    await request_weight_load(dut)
    await send_weight_rows(dut, weights)
    return weights, biases

async def send_activation(dut, activation, last=False):
    dut.s_axis_a_tdata.value = pack_signed_lanes(activation, DW)
    dut.s_axis_a_tlast.value = int(last)
    dut.s_axis_a_tvalid.value = 1
    for _ in range(TIMEOUT):
        snapshot = await cycle(dut)
        if snapshot["a_fire"]:
            dut.s_axis_a_tvalid.value = 0
            dut.s_axis_a_tlast.value = 0
            return
    raise AssertionError("Timed out waiting for activation handshake")

def check_output(dut, snapshot, pending, received):
    if not snapshot["m_fire"]:
        return
    assert pending, "Output transfer without a matching accepted input"
    index, expected_data, expected_last = pending.popleft()
    actual_data = output_lanes(snapshot["m_data"])

    assert actual_data == expected_data, (f"Transaction {index}: expected {expected_data}, got {actual_data}")
    assert snapshot["m_last"] == int(expected_last), (f"Transaction {index}: expected TLAST={int(expected_last)}, " f"got {snapshot['m_last']}")
    expected_done = int(expected_last)
    assert int(dut.o_done.value) == expected_done, (f"Transaction {index}: expected o_done={expected_done}, " f"got {int(dut.o_done.value)}")
    received.append(index)

async def send_stream(dut, transactions, weights, biases):
    pending = deque()
    received = []

    for index, (activation, last) in enumerate(transactions):
        dut.s_axis_a_tdata.value = pack_signed_lanes(activation, DW)
        dut.s_axis_a_tlast.value = int(last)
        dut.s_axis_a_tvalid.value = 1
        snapshot = await cycle(dut)
        check_output(dut, snapshot, pending, received)
        assert snapshot["a_fire"], f"Input transaction {index} was not accepted"
        pending.append((index, expected_output(activation, weights, biases), last))

    dut.s_axis_a_tvalid.value = 0
    dut.s_axis_a_tlast.value = 0

    for _ in range(TIMEOUT * max(1, len(transactions))):
        if len(received) == len(transactions):
            break
        snapshot = await cycle(dut)
        check_output(dut, snapshot, pending, received)

    assert len(received) == len(transactions), (f"Expected {len(transactions)} output transfers, got {len(received)}")
    assert not pending

@cocotb.test()
async def test_single_vector_latency_and_value(dut):
    weights, biases = await prepare(dut, 101)
    activation = [3, -2, 7, -8, 0, 127, -128, 11]
    expected = expected_output(activation, weights, biases)

    await send_activation(dut, activation, last=True)

    for cycle_index in range(LAT - 2):
        await cycle(dut)
        assert int(dut.m_axis_c_tvalid.value) == 0, (f"Output valid asserted early at post-accept cycle {cycle_index + 1}")
    await cycle(dut)
    assert int(dut.m_axis_c_tvalid.value) == 1, (f"Output valid did not assert after {LAT - 1} advancing cycles")
    assert output_lanes(int(dut.m_axis_c_tdata.value)) == expected
    assert int(dut.m_axis_c_tlast.value) == 1

    snapshot = await cycle(dut)
    assert snapshot["m_fire"]
    assert output_lanes(snapshot["m_data"]) == expected
    assert snapshot["m_last"] == 1
    assert int(dut.o_done.value) == 1

@cocotb.test()
async def test_back_to_back_vectors(dut):
    weights, biases = await prepare(dut, 202)
    rng = random.Random(202)
    transactions = [([rng.randint(-128, 127) for _ in range(N)], index == 2*LAT + 2) for index in range(2*LAT + 3)]
    await send_stream(dut, transactions, weights, biases)

@cocotb.test()
async def test_output_stall_stability(dut):
    weights, biases = await prepare(dut, 303)
    activation = [-128, 127, 1, -1, 64, -64, 5, 9]
    expected = expected_output(activation, weights, biases)
    dut.m_axis_c_tready.value = 0
    await send_activation(dut, activation, last=True)

    for cycle_index in range(LAT - 2):
        await cycle(dut)
        assert int(dut.m_axis_c_tvalid.value) == 0, (f"Output valid asserted early at cycle {cycle_index + 1}")

    await cycle(dut)
    assert int(dut.m_axis_c_tvalid.value) == 1
    held_data = int(dut.m_axis_c_tdata.value)
    held_last = int(dut.m_axis_c_tlast.value)
    assert output_lanes(held_data) == expected
    assert held_last == 1

    for _ in range(5):
        snapshot = await cycle(dut)
        assert snapshot["m_valid"] == 1
        assert snapshot["m_ready"] == 0
        assert snapshot["m_fire"] == 0
        assert snapshot["m_data"] == held_data
        assert snapshot["m_last"] == held_last

    dut.m_axis_c_tready.value = 1
    snapshot = await cycle(dut)
    assert snapshot["m_fire"]
    assert snapshot["m_data"] == held_data
    assert snapshot["m_last"] == held_last
    assert int(dut.o_done.value) == 1

@cocotb.test()
async def test_tlast_stays_with_transaction(dut):
    weights, biases = await prepare(dut, 404)
    rng = random.Random(404)
    transactions = [([rng.randint(-128, 127) for _ in range(N)], last) for last in (False, True, False, False)]
    await send_stream(dut, transactions, weights, biases)

@cocotb.test()
async def test_stall_resume_no_loss_or_reordering(dut):
    weights, biases = await prepare(dut, 505)
    rng = random.Random(505)
    transactions = [([rng.randint(-128, 127) for _ in range(N)], last) for last in (False, False, True, False, False, True, True)]
    pending = deque()
    received = []
    dut.m_axis_c_tready.value = 0

    for index, (activation, last) in enumerate(transactions[:-1]):
        dut.s_axis_a_tdata.value = pack_signed_lanes(activation, DW)
        dut.s_axis_a_tlast.value = int(last)
        dut.s_axis_a_tvalid.value = 1
        snapshot = await cycle(dut)
        check_output(dut, snapshot, pending, received)
        assert snapshot["a_fire"], f"Input transaction {index} was not accepted"
        pending.append((index, expected_output(activation, weights, biases), last))

    dut.s_axis_a_tvalid.value = 0
    dut.s_axis_a_tlast.value = 0

    for _ in range(LAT + 2):
        await cycle(dut)
        if int(dut.m_axis_c_tvalid.value):
            break
    else:
        raise AssertionError("Output did not become valid")

    held_data = int(dut.m_axis_c_tdata.value)
    held_last = int(dut.m_axis_c_tlast.value)
    pending_activation, pending_last = transactions[-1]
    pending_data = pack_signed_lanes(pending_activation, DW)
    dut.s_axis_a_tdata.value = pending_data
    dut.s_axis_a_tlast.value = int(pending_last)
    dut.s_axis_a_tvalid.value = 1

    for _ in range(6):
        snapshot = await cycle(dut)
        assert snapshot["m_valid"] == 1
        assert snapshot["m_ready"] == 0
        assert snapshot["m_fire"] == 0
        assert snapshot["m_data"] == held_data
        assert snapshot["m_last"] == held_last
        assert snapshot["a_ready"] == 0
        assert snapshot["a_fire"] == 0
        assert int(dut.s_axis_a_tdata.value) == pending_data
        assert int(dut.s_axis_a_tlast.value) == int(pending_last)

    dut.m_axis_c_tready.value = 1
    snapshot = await cycle(dut)
    check_output(dut, snapshot, pending, received)
    assert snapshot["a_fire"], "Pending input was not accepted after output resumed"
    pending.append((len(transactions) - 1, expected_output(pending_activation, weights, biases), pending_last))
    dut.s_axis_a_tvalid.value = 0
    dut.s_axis_a_tlast.value = 0

    for _ in range(TIMEOUT * len(transactions)):
        if len(received) == len(transactions):
            break
        snapshot = await cycle(dut)
        check_output(dut, snapshot, pending, received)

    assert received == list(range(len(transactions))), (f"Output order mismatch: {received}")
    assert not pending


@cocotb.test()
async def test_weight_load_deferred_until_pipeline_drains(dut):
    weights, biases = await prepare(dut, 606)
    activation = [12, -7, 2, 64, -91, 3, 55, -100]
    expected_old = expected_output(activation, weights, biases)

    dut.m_axis_c_tready.value = 0
    await send_activation(dut, activation, last=True)

    for _ in range(LAT - 2):
        await cycle(dut)
        assert int(dut.m_axis_c_tvalid.value) == 0

    await cycle(dut)
    assert int(dut.m_axis_c_tvalid.value) == 1
    held_data = int(dut.m_axis_c_tdata.value)
    assert output_lanes(held_data) == expected_old

    dut.i_load_w.value = 1
    await cycle(dut)
    dut.i_load_w.value = 0

    assert int(dut.o_weights_loaded.value) == 0
    assert int(dut.s_axis_w_tready.value) == 0
    assert int(dut.s_axis_a_tready.value) == 0
    assert int(dut.m_axis_c_tvalid.value) == 1

    for _ in range(3):
        snapshot = await cycle(dut)
        assert snapshot["m_valid"] == 1
        assert snapshot["m_ready"] == 0
        assert snapshot["m_data"] == held_data
        assert snapshot["m_last"] == 1
        assert snapshot["w_ready"] == 0

    dut.m_axis_c_tready.value = 1
    snapshot = await cycle(dut)
    assert snapshot["m_fire"]
    assert output_lanes(snapshot["m_data"]) == expected_old
    assert snapshot["m_last"] == 1
    assert int(dut.o_done.value) == 1
    assert int(dut.s_axis_w_tready.value) == 0

    await cycle(dut)
    assert int(dut.s_axis_w_tready.value) == 1

    new_weights, _ = make_case(607)
    await send_weight_rows(dut, new_weights)
    assert int(dut.o_weights_loaded.value) == 1

    dut.m_axis_c_tready.value = 1
    new_activation = [-1, 4, 8, 16, -32, 64, -128, 127]
    expected_new = expected_output(new_activation, new_weights, biases)
    await send_activation(dut, new_activation, last=True)

    for _ in range(LAT - 1):
        await cycle(dut)
    assert int(dut.m_axis_c_tvalid.value) == 1
    assert output_lanes(int(dut.m_axis_c_tdata.value)) == expected_new

    snapshot = await cycle(dut)
    assert snapshot["m_fire"]
    assert output_lanes(snapshot["m_data"]) == expected_new
    assert snapshot["m_last"] == 1
    assert int(dut.o_done.value) == 1
