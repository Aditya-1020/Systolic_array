import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from generic import pack_signed_lanes, wait_clock_cycles


N = 8
DW = 8
Q_W = DW
OUT_W = 32
MEM_DW = 64
BEAT_BYTES = MEM_DW // 8
NB = (N * OUT_W) // MEM_DW
ACT_BASE = 0x1000
WEIGHT_BASE = 0x2000
BIAS_BASE = 0x3000
DST_BASE = 0x4000


async def setup(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0

    defaults = {
        "i_load_weights": 0,
        "i_start": 0,
        "i_abort": 0,
        "i_soft_reset": 0,
        "i_arr_en": 1,
        "i_bias_en": 0,
        "i_bias_base": BIAS_BASE,
        "i_weight_base": WEIGHT_BASE,
        "i_act_base": ACT_BASE,
        "i_dst_base": DST_BASE,
        "i_act_count": 1,
        "i_weights_loaded": 0,
        "i_quant_en_q": 0,
        "mem_rd_req_ready": 0,
        "mem_rd_rsp_valid": 0,
        "mem_rd_rsp_data": 0,
        "mem_rd_rsp_error": 0,
        "mem_wr_req_ready": 0,
        "mem_wr_rsp_valid": 0,
        "mem_wr_rsp_error": 0,
        "s_axis_w_tready": 1,
        "s_axis_a_tready": 1,
        "m_axis_c_tvalid": 0,
        "m_axis_c_tdata": 0,
        "m_axis_c_tlast": 0,
    }

    for name, value in defaults.items():
        getattr(dut, name).value = value

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await Timer(20, unit="ns")
    dut.i_rstn.value = 1
    await wait_clock_cycles(dut, 2, "i_clk")


async def cycle(dut):
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def command(dut, signal):
    await FallingEdge(dut.i_clk)
    getattr(dut, signal).value = 1
    await RisingEdge(dut.i_clk)
    await FallingEdge(dut.i_clk)
    getattr(dut, signal).value = 0
    await Timer(1, unit="ns")


async def start_run(dut, count=1, quant=0):
    dut.i_weights_loaded.value = 1
    dut.i_act_count.value = count
    dut.i_quant_en_q.value = quant
    await command(dut, "i_start")
    assert int(dut.o_computing.value) == 1


async def read_request(dut, limit=100):
    for _ in range(limit):
        await FallingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.mem_rd_req_valid.value):
            addr = int(dut.mem_rd_req_addr.value)
            dut.mem_rd_req_ready.value = 1
            await Timer(1, unit="ns")
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            await FallingEdge(dut.i_clk)
            dut.mem_rd_req_ready.value = 0
            await Timer(1, unit="ns")
            return addr
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    raise AssertionError("Timed out waiting for memory read request")


async def read_response(dut, data=0, error=0, limit=100):
    await FallingEdge(dut.i_clk)
    dut.mem_rd_rsp_data.value = data
    dut.mem_rd_rsp_error.value = error
    dut.mem_rd_rsp_valid.value = 1
    await Timer(1, unit="ns")

    for _ in range(limit):
        if int(dut.mem_rd_rsp_ready.value):
            weight_fire = (
                int(dut.s_axis_w_tvalid.value) and
                int(dut.s_axis_w_tready.value)
            )
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            await FallingEdge(dut.i_clk)
            dut.mem_rd_rsp_valid.value = 0
            dut.mem_rd_rsp_error.value = 0
            await Timer(1, unit="ns")
            return int(weight_fire)

        await RisingEdge(dut.i_clk)
        await FallingEdge(dut.i_clk)
        await Timer(1, unit="ns")

    raise AssertionError("Timed out waiting for read response acceptance")


async def write_request(dut, limit=100):
    for _ in range(limit):
        await FallingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.mem_wr_req_valid.value):
            addr = int(dut.mem_wr_req_addr.value)
            data = int(dut.mem_wr_req_data.value)
            dut.mem_wr_req_ready.value = 1
            await Timer(1, unit="ns")
            ready = int(dut.m_axis_c_tready.value)
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            await FallingEdge(dut.i_clk)
            dut.mem_wr_req_ready.value = 0
            await Timer(1, unit="ns")
            return addr, data, ready

        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")

    raise AssertionError("Timed out waiting for memory write request")


async def write_response(dut, error=0):
    await FallingEdge(dut.i_clk)
    dut.mem_wr_rsp_error.value = error
    dut.mem_wr_rsp_valid.value = 1
    await Timer(1, unit="ns")

    assert int(dut.mem_wr_rsp_ready.value) == 1
    err = int(dut.o_err_write.value)
    abort = int(dut.o_arr_abort.value)

    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    await FallingEdge(dut.i_clk)
    dut.mem_wr_rsp_valid.value = 0
    dut.mem_wr_rsp_error.value = 0
    await Timer(1, unit="ns")

    return err, abort


async def wait_idle(dut, limit=100):
    for _ in range(limit):
        if int(dut.o_busy.value) == 0:
            return
        await cycle(dut)
    raise AssertionError("DMA did not return to idle")


async def load_weights(dut, bias=0):
    dut.i_bias_en.value = bias
    await command(dut, "i_load_weights")


async def complete_load(dut, total, bias_beats=0):
    weight_count = 0
    bias_count = 0
    weight_transfers = 0

    for index in range(total):
        addr = await read_request(dut)

        if index < bias_beats:
            assert addr == BIAS_BASE + index * BEAT_BYTES
            bias_count += 1
        else:
            expected = WEIGHT_BASE + (index - bias_beats) * BEAT_BYTES
            assert addr == expected
            weight_count += 1

        weight_transfers += await read_response(dut, data=index + 1)

    await wait_idle(dut)
    assert weight_count == N
    assert bias_count == bias_beats
    assert weight_transfers == N


async def send_activations(dut, count):
    for index in range(count):
        addr = await read_request(dut)
        assert addr == ACT_BASE + index * BEAT_BYTES
        await read_response(dut, data=index + 1)


@cocotb.test()
async def test_weight_load_without_bias(dut):
    await setup(dut)
    await load_weights(dut, bias=0)

    addresses = []
    weight_transfers = 0

    for index in range(N):
        addresses.append(await read_request(dut))
        weight_transfers += await read_response(dut, data=index + 1)

    assert addresses == [WEIGHT_BASE + i * BEAT_BYTES for i in range(N)]
    assert weight_transfers == N
    await wait_idle(dut)


@cocotb.test()
async def test_weight_load_with_bias(dut):
    await setup(dut)
    await load_weights(dut, bias=1)
    await complete_load(dut, N + NB, bias_beats=NB)


@cocotb.test()
async def test_four_outstanding_reads_switch_bias_to_weights(dut):
    await setup(dut)
    dut.i_bias_en.value = 1
    await command(dut, "i_load_weights")

    addresses = []

    for _ in range(4):
        addresses.append(await read_request(dut))

    assert addresses == [BIAS_BASE + i * BEAT_BYTES for i in range(4)]

    weight_transfers = 0

    for index in range(4):
        weight_transfers += await read_response(dut, data=index + 1)

    for index in range(NB + N - 4):
        addresses.append(await read_request(dut))
        weight_transfers += await read_response(dut, data=index + 5)

    expected = (
        [BIAS_BASE + i * BEAT_BYTES for i in range(NB)] +
        [WEIGHT_BASE + i * BEAT_BYTES for i in range(N)]
    )

    assert addresses == expected
    assert weight_transfers == N
    await wait_idle(dut)


@cocotb.test()
async def test_activation_backpressure(dut):
    await setup(dut)
    dut.s_axis_a_tready.value = 0
    await start_run(dut, count=1)

    await read_request(dut)

    data = pack_signed_lanes([1, 2, 3, 4, 5, 6, 7, 8], DW)

    await FallingEdge(dut.i_clk)
    dut.mem_rd_rsp_data.value = data
    dut.mem_rd_rsp_valid.value = 1
    await Timer(1, unit="ns")

    assert int(dut.mem_rd_rsp_ready.value) == 0
    assert int(dut.s_axis_a_tvalid.value) == 1
    assert int(dut.s_axis_a_tdata.value) == data
    assert int(dut.s_axis_a_tlast.value) == 1

    await cycle(dut)

    assert int(dut.mem_rd_rsp_valid.value) == 1
    assert int(dut.s_axis_a_tdata.value) == data

    dut.s_axis_a_tready.value = 1
    await cycle(dut)

    await FallingEdge(dut.i_clk)
    dut.mem_rd_rsp_valid.value = 0
    await Timer(1, unit="ns")


@cocotb.test()
async def test_quantized_output_one_beat(dut):
    await setup(dut)
    await start_run(dut, count=1, quant=1)
    await send_activations(dut, 1)

    lanes = [3, -2, 7, -8, 11, -12, 15, -16]
    full_values = [value & ((1 << OUT_W) - 1) for value in lanes]
    output = sum(value << (index * OUT_W) for index, value in enumerate(full_values))
    expected = pack_signed_lanes(lanes, Q_W)

    dut.m_axis_c_tdata.value = output
    dut.m_axis_c_tlast.value = 1
    dut.m_axis_c_tvalid.value = 1

    addr, data, ready = await write_request(dut)

    assert addr == DST_BASE
    assert data == expected
    assert ready == 1

    await FallingEdge(dut.i_clk)
    dut.m_axis_c_tvalid.value = 0
    dut.m_axis_c_tlast.value = 0
    await Timer(1, unit="ns")

    await write_response(dut)


@cocotb.test()
async def test_multiple_output_vectors_and_write_addresses(dut):
    await setup(dut)
    await start_run(dut, count=2, quant=0)
    await send_activations(dut, 2)

    vectors = [
        [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88],
        [0x91, 0xA2, 0xB3, 0xC4, 0xD5, 0xE6, 0xF7, 0x08],
    ]

    addresses = []

    for vector_index, lanes in enumerate(vectors):
        output = sum(
            (value & 0xFFFFFFFF) << (index * OUT_W)
            for index, value in enumerate(lanes)
        )

        dut.m_axis_c_tdata.value = output
        dut.m_axis_c_tlast.value = int(vector_index == len(vectors) - 1)
        dut.m_axis_c_tvalid.value = 1

        final_ready = 0

        for beat in range(NB):
            addr, data, final_ready = await write_request(dut)
            addresses.append(addr)

            expected = (output >> (beat * MEM_DW)) & ((1 << MEM_DW) - 1)
            assert data == expected

            if beat == NB - 1:
                dut.m_axis_c_tvalid.value = 0
                dut.m_axis_c_tlast.value = 0

            await write_response(dut)

        assert final_ready == 1
        await cycle(dut)

    expected_addresses = [
        DST_BASE + index * BEAT_BYTES for index in range(2 * NB)
    ]
    assert addresses == expected_addresses


@cocotb.test()
async def test_write_response_error(dut):
    await setup(dut)
    await start_run(dut, count=1, quant=1)
    await send_activations(dut, 1)

    dut.m_axis_c_tdata.value = 0x1234
    dut.m_axis_c_tlast.value = 1
    dut.m_axis_c_tvalid.value = 1

    await write_request(dut)

    dut.m_axis_c_tvalid.value = 0
    dut.m_axis_c_tlast.value = 0

    err, abort = await write_response(dut, error=1)

    assert err == 1
    assert abort == 1
    await wait_idle(dut)


@cocotb.test()
async def test_abort_with_outstanding_reads(dut):
    await setup(dut)
    await start_run(dut, count=8)

    for _ in range(2):
        await read_request(dut)

    await command(dut, "i_abort")
    assert int(dut.mem_rd_req_valid.value) == 0

    await read_response(dut, data=0x11)
    await read_response(dut, data=0x22)
    await wait_idle(dut)


@cocotb.test()
async def test_abort_with_outstanding_writes(dut):
    await setup(dut)
    await start_run(dut, count=1, quant=1)
    await send_activations(dut, 1)

    dut.m_axis_c_tdata.value = 0x1234
    dut.m_axis_c_tlast.value = 1
    dut.m_axis_c_tvalid.value = 1

    await write_request(dut)
    dut.m_axis_c_tvalid.value = 0
    dut.m_axis_c_tlast.value = 0

    await command(dut, "i_abort")

    assert int(dut.mem_wr_req_valid.value) == 0

    await write_response(dut)
    await wait_idle(dut)


@cocotb.test()
async def test_done_after_all_write_responses(dut):
    await setup(dut)
    await start_run(dut, count=1, quant=0)
    await send_activations(dut, 1)

    output = int("12" * (N * OUT_W // 8), 16)
    dut.m_axis_c_tdata.value = output
    dut.m_axis_c_tlast.value = 1
    dut.m_axis_c_tvalid.value = 1

    final_ready = 0

    for _ in range(NB):
        _, _, final_ready = await write_request(dut)

    assert final_ready == 1

    dut.m_axis_c_tvalid.value = 0
    dut.m_axis_c_tlast.value = 0

    assert int(dut.o_done.value) == 0

    for _ in range(NB - 1):
        await write_response(dut)
        assert int(dut.o_done.value) == 0

    await write_response(dut)
    assert int(dut.o_done.value) == 1

    await cycle(dut)
    assert int(dut.o_done.value) == 0
    await wait_idle(dut)
