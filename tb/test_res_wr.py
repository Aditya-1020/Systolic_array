import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

N = 8
ACC_W = 19
RAW_BEATS = 4
MASK64 = (1 << 64) - 1


def pack_raw(values):
    mask = (1 << ACC_W) - 1
    return sum((value & mask) << (lane * ACC_W) for lane, value in enumerate(values))


def expected_raw_beats(values):
    result = []
    for beat in range(RAW_BEATS):
        lo = values[2 * beat] & 0xFFFFFFFF
        hi = values[2 * beat + 1] & 0xFFFFFFFF
        result.append(lo | (hi << 32))
    return result


async def initialize(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rstn.value = 0
    dut.i_run_start.value = 0
    dut.i_mode.value = 0
    dut.i_caddr.value = 0
    dut.i_count.value = 0
    dut.i_pp_valid.value = 0
    dut.i_pp_data.value = 0
    dut.i_raw_valid.value = 0
    dut.i_raw_data.value = 0
    for _ in range(4):
        await RisingEdge(dut.i_clk)
    await FallingEdge(dut.i_clk)
    dut.i_rstn.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def start_run(dut, mode, base, count):
    await FallingEdge(dut.i_clk)
    dut.i_mode.value = mode
    dut.i_caddr.value = base
    dut.i_count.value = count
    dut.i_run_start.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_run_start.value = 0
    assert int(dut.o_all_written.value) == 0


async def collect_writes(dut, cycles):
    writes = []
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if int(dut.o_rbuf_req.value):
            writes.append((
                int(dut.o_rbuf_addr.value),
                int(dut.o_rbuf_wdata.value),
                int(dut.o_rbuf_wmask.value),
            ))
    return writes


async def send_pp_row(dut, data):
    await FallingEdge(dut.i_clk)
    dut.i_pp_data.value = data
    dut.i_pp_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_pp_valid.value = 0
    return await collect_writes(dut, 3)


async def send_raw_row(dut, values):
    await FallingEdge(dut.i_clk)
    dut.i_raw_data.value = pack_raw(values)
    dut.i_raw_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_raw_valid.value = 0
    return await collect_writes(dut, 7)


@cocotb.test()
async def test_res_wr_int8_rows_increment_one_address(dut):
    await initialize(dut)
    await start_run(dut, mode=0, base=23, count=2)

    row0 = 0x0123456789ABCDEF
    row1 = 0xFEDCBA9876543210

    writes0 = await send_pp_row(dut, row0)
    assert writes0 == [(23, row0, MASK64)], f"first row writes: {writes0}"
    assert int(dut.o_all_written.value) == 0

    writes1 = await send_pp_row(dut, row1)
    assert writes1 == [(24, row1, MASK64)], f"second row writes: {writes1}"
    assert int(dut.o_all_written.value) == 1


@cocotb.test()
async def test_res_wr_raw_beats_and_row_stride(dut):
    await initialize(dut)
    await start_run(dut, mode=1, base=100, count=2)

    rows = [
        [-200000, -1, 0, 1, 2, -2, 0x12345, -0x12345],
        [0x1FFFF, -0x20000, 17, -19, 101, -103, 255, -257],
    ]

    for row_index, values in enumerate(rows):
        writes = await send_raw_row(dut, values)
        base = 100 + row_index * RAW_BEATS
        expected_data = expected_raw_beats(values)
        expected = [
            (base + beat, expected_data[beat], MASK64)
            for beat in range(RAW_BEATS)
        ]
        assert writes == expected, (
            f"raw row {row_index}: expected {expected}, got {writes}"
        )

    assert int(dut.o_all_written.value) == 1
