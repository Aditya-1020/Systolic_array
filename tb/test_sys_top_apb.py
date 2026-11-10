import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer

from ctrl_model import (
    N, DW, RAW_BEATS, MAX_ROWS, SEED,
    random_matrix, golden_i8, golden_raw,
    pack_lanes, wrap_signed
)

CSR_ID = 0x00
CSR_CTRL = 0x04
CSR_STATUS = 0x08
CSR_DIM = 0x0C
CSR_WADDR = 0x10
CSR_AADDR = 0x14
CSR_CADDR = 0x18
CSR_COUNT = 0x1C
CSR_PPCFG = 0x20

# CTRL
CTRL_START = 1 << 0
CTRL_W_LOAD = 1 << 1
CTRL_IRQ_EN = 1 << 2

# STATUS
STATUS_BUSY = 1 << 0
STATUS_DONE = 1 << 1
STATUS_ERR = 1 << 2

# PPCFG
PPCFG_PP_EN = 1 << 0
PPCFG_RELU = 1 << 1
PPCFG_ROUND = 1 << 2
PPCFG_SHIFT_LSB = 8

# Memory windows
WBUF_BASE = 0x1000
ABUF_BASE = 0x2000
RBUF_BASE = 0x3000

BEAT_BYTES = 8
TIMEOUT = 20000
APB_TIMEOUT = 128

def apb_clk(dut):
    """Independent APB input clock."""
    return dut.i_clk_apb

async def apb_write(dut, addr, data, strobe=0xF):
    clk = apb_clk(dut)
    await FallingEdge(clk)
    dut.i_psel.value = 1
    dut.i_penable.value = 0
    dut.i_pwrite.value = 1
    dut.i_pprot.value = 0
    dut.i_paddr.value = addr
    dut.i_pwdata.value = data & 0xFFFFFFFF
    dut.i_pstrb.value = strobe & 0xF
    await RisingEdge(clk)
    await FallingEdge(clk)
    dut.i_penable.value = 1

    for _ in range(APB_TIMEOUT):
        await Timer(1, unit="ns")
        if int(dut.o_pready.value):
            assert int(dut.o_pslverr.value) == 0, (
                f"APB write error: addr=0x{addr:04x}, "
                f"data=0x{data:08x}"
            )
            await RisingEdge(clk)
            break
        await RisingEdge(clk)
        await FallingEdge(clk)
    else:
        raise AssertionError(f"APB write timeout: addr=0x{addr:04x}")

    await FallingEdge(clk)
    dut.i_psel.value = 0
    dut.i_penable.value = 0
    dut.i_pwrite.value = 0
    dut.i_pstrb.value = 0

async def apb_read(dut, addr):
    clk = apb_clk(dut)
    await FallingEdge(clk)
    dut.i_psel.value = 1
    dut.i_penable.value = 0
    dut.i_pwrite.value = 0
    dut.i_pprot.value = 0
    dut.i_paddr.value = addr
    dut.i_pwdata.value = 0
    dut.i_pstrb.value = 0
    await RisingEdge(clk)
    await FallingEdge(clk)
    dut.i_penable.value = 1

    for _ in range(APB_TIMEOUT):
        await Timer(1, unit="ns")
        if int(dut.o_pready.value):
            assert int(dut.o_pslverr.value) == 0, (
                f"APB read error: addr=0x{addr:04x}"
            )
            data = int(dut.o_prdata.value)
            await RisingEdge(clk)
            break
        await RisingEdge(clk)
        await FallingEdge(clk)
    else:
        raise AssertionError(f"APB read timeout: addr=0x{addr:04x}")

    await FallingEdge(clk)
    dut.i_psel.value = 0
    dut.i_penable.value = 0
    return data

async def apb_write64(dut, addr, data):
    await apb_write(dut, addr, data & 0xFFFFFFFF)
    await apb_write(dut, addr + 4, (data >> 32) & 0xFFFFFFFF)

async def apb_read64(dut, addr):
    low = await apb_read(dut, addr)
    high = await apb_read(dut, addr + 4)
    return low | (high << 32)

async def write_buffer(dut, base, rows):
    for index, row in enumerate(rows):
        data = pack_lanes(row, DW)
        addr = base + index * BEAT_BYTES
        await apb_write64(dut, addr, data)

async def read_results(dut, base, count, beats=1):
    results = []
    for row in range(count):
        row_data = []
        for beat in range(beats):
            addr = base + (row * beats + beat) * BEAT_BYTES
            row_data.append(await apb_read64(dut, addr))
        results.append(row_data)
    return results

async def reset_dut(dut):
    dut.i_psel.value = 0
    dut.i_penable.value = 0
    dut.i_pwrite.value = 0
    dut.i_pprot.value = 0
    dut.i_paddr.value = 0
    dut.i_pwdata.value = 0
    dut.i_pstrb.value = 0
    dut.i_arst_n.value = 0

    for _ in range(8):
        await RisingEdge(dut.i_clk_core)

    await FallingEdge(dut.i_clk_core)
    dut.i_arst_n.value = 1

    # Independent reset synchronizers need edges after release.
    for _ in range(8):
        await RisingEdge(dut.i_clk)
    for _ in range(4):
        await RisingEdge(apb_clk(dut))

async def initialize(dut):
    # Core and APB clocks are independently driven at 200 MHz and 100 MHz.
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    await reset_dut(dut)


async def configure_job(
    dut, waddr, aaddr, caddr, count,
    pp_en, relu, rounding, shift, w_load=1
):
    ppcfg = (
        (PPCFG_PP_EN if pp_en else 0)
        | (PPCFG_RELU if relu else 0)
        | (PPCFG_ROUND if rounding else 0)
        | (shift << PPCFG_SHIFT_LSB)
    )
    ctrl = CTRL_IRQ_EN | (CTRL_W_LOAD if w_load else 0)

    await apb_write(dut, CSR_WADDR, waddr)
    await apb_write(dut, CSR_AADDR, aaddr)
    await apb_write(dut, CSR_CADDR, caddr)
    await apb_write(dut, CSR_COUNT, count)
    await apb_write(dut, CSR_PPCFG, ppcfg)
    await apb_write(dut, CSR_CTRL, ctrl | CTRL_START)


def peek(dut, path):
    try:
        signal = dut
        for name in path.split("."):
            signal = getattr(signal, name)
        return int(signal.value)
    except Exception:
        return None

async def wait_done(dut, timeout=TIMEOUT):
    seen_busy = False
    done_seen = False
    last_status = 0

    for cycle in range(timeout):
        status = await apb_read(dut, CSR_STATUS)
        last_status = status
        seen_busy |= bool(status & STATUS_BUSY)
        done_seen |= bool(status & STATUS_DONE)

        if status & STATUS_ERR:
            raise AssertionError(
                f"Accelerator ERR at poll {cycle}: STATUS=0x{status:08X} "
                f"busy={peek(dut, 'busy')} err_set={peek(dut, 'err_set')} "
                f"state={peek(dut, 'seq_state')} bad_q={peek(dut, 'u_seq_ctrl.bad_q')}"
            )

        # Require BUSY seen so a sticky DONE from the previous job cannot
        # satisfy completion before the new run has started.
        if seen_busy and done_seen and not (status & STATUS_BUSY):
            return status

    raise AssertionError(
        f"Accelerator completion timeout: STATUS=0x{last_status:08X} "
        f"busy_seen={seen_busy} done_seen={done_seen} "
        f"busy={peek(dut, 'busy')} state={peek(dut, 'seq_state')} "
        f"all_written={peek(dut, 'all_written')}"
    )


async def check_int8(dut, expected, caddr):
    base = RBUF_BASE + caddr * BEAT_BYTES
    actual = await read_results(dut, base, len(expected))

    for row in range(len(expected)):
        got = [
            wrap_signed((actual[row][0] >> (col * DW)) & 0xFF, DW)
            for col in range(N)
        ]
        assert got == expected[row], (
            f"INT8 row {row}: "
            f"expected={expected[row]}, got={got}"
        )

async def check_raw(dut, expected, caddr):
    base = RBUF_BASE + caddr * BEAT_BYTES
    actual = await read_results(dut, base, len(expected), RAW_BEATS)

    for row in range(len(expected)):
        for beat in range(RAW_BEATS):
            got = actual[row][beat]
            exp = expected[row][beat]
            assert got == exp, (
                f"RAW row={row} beat={beat}: "
                f"expected=0x{exp:016x}, got=0x{got:016x}"
            )

async def run_int8_job(
    dut, weights, activations,
    waddr=0, aaddr=0, caddr=0,
    shift=9, rounding=1, relu=1, w_load=1
):
    expected = golden_i8(activations, weights, shift, rounding, relu)

    if w_load:
        await write_buffer(dut, WBUF_BASE + waddr * BEAT_BYTES, weights)

    await write_buffer(dut, ABUF_BASE + aaddr * BEAT_BYTES, activations)

    await configure_job(
        dut, waddr, aaddr, caddr, len(activations),
        1, relu, rounding, shift, w_load
    )
    await wait_done(dut)
    await check_int8(dut, expected, caddr)

async def run_raw_job(
    dut, weights, activations,
    waddr=0, aaddr=0, caddr=0, w_load=1
):
    expected = golden_raw(activations, weights)

    if w_load:
        await write_buffer(dut, WBUF_BASE + waddr * BEAT_BYTES, weights)

    await write_buffer(dut, ABUF_BASE + aaddr * BEAT_BYTES, activations)

    await configure_job(
        dut, waddr, aaddr, caddr, len(activations),
        0, 0, 0, 0, w_load
    )
    await wait_done(dut)
    await check_raw(dut, expected, caddr)

@cocotb.test()
async def test_sys_top_apb_buffer_write_readback(dut):
    await initialize(dut)
    patterns = [
        0x0123456789ABCDEF,
        0xFEDCBA9876543210,
        0xAAAAAAAA55555555,
        0x80017FFE00FFAA55,
    ]
    for base, label in ((WBUF_BASE, "WBUF"), (ABUF_BASE, "ABUF")):
        for index, expected in enumerate(patterns):
            await apb_write64(dut, base + index * BEAT_BYTES, expected)
        for index, expected in enumerate(patterns):
            actual = await apb_read64(dut, base + index * BEAT_BYTES)
            assert actual == expected, (
                f"{label} beat {index}: expected=0x{expected:016X} got=0x{actual:016X}"
            )

@cocotb.test()
async def test_sys_top_apb_csr_readback(dut):
    await initialize(dut)
    assert await apb_read(dut, CSR_ID) == 0x5A010002
    assert await apb_read(dut, CSR_DIM) == 0x40130808
    assert await apb_read(dut, CSR_CTRL) == 0
    assert await apb_read(dut, CSR_STATUS) == 0
    dut._log.info("CSR readback PASS")

@cocotb.test()
async def test_sys_top_apb_int8_gemm(dut):
    await initialize(dut)
    rng = random.Random(SEED)
    weights = random_matrix(rng, N)
    activations = random_matrix(rng, 20)
    await run_int8_job(
        dut, weights, activations,
        waddr=8, aaddr=3, caddr=5,
        shift=9, rounding=1, relu=1
    )

@cocotb.test()
async def test_sys_top_apb_int8_resident_weights(dut):
    await initialize(dut)
    rng = random.Random(SEED + 1)
    weights = random_matrix(rng, N)
    first_activations = random_matrix(rng, 1)
    second_activations = random_matrix(rng, 33)

    # First run loads weights into the datapath.
    await run_int8_job(
        dut, weights, first_activations,
        waddr=0, aaddr=0, caddr=0,
        shift=7, rounding=0, relu=0, w_load=1
    )
    # Second run: same as original resident test.
    await run_int8_job(
        dut, weights, second_activations,
        waddr=0, aaddr=1, caddr=40,
        shift=7, rounding=0, relu=0, w_load=0
    )

@cocotb.test()
async def test_sys_top_apb_raw_gemm(dut):
    await initialize(dut)
    rng = random.Random(SEED + 2)
    weights = random_matrix(rng, N)
    activations = random_matrix(rng, 10)
    await run_raw_job(
        dut, weights, activations,
        waddr=0, aaddr=10, caddr=16
    )

@cocotb.test()
async def test_sys_top_apb_raw_max_rows(dut):
    await initialize(dut)
    rng = random.Random(SEED + 3)
    weights = random_matrix(rng, N)
    activations = random_matrix(rng, MAX_ROWS)
    await run_raw_job(
        dut, weights, activations,
        waddr=0, aaddr=0, caddr=0, w_load=1
    )

@cocotb.test()
async def test_sys_top_apb_int8_extreme_values(dut):
    await initialize(dut)
    weights = [[-128] * N for _ in range(N)]
    activations = [[-128] * N]
    await run_int8_job(
        dut, weights, activations,
        waddr=0, aaddr=0, caddr=0,
        shift=18, rounding=1, relu=0
    )