import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from generic import pack_signed_lanes, unpack_signed_lanes, wrap_signed


N = 8
DW = 8
Q_W = DW
OUT_W = 32
BIAS_W = 16
ACC_W = 2 * DW + 3
MEM_DW = N * DW
BEAT_BYTES = MEM_DW // 8
BEAT_MASK = (1 << MEM_DW) - 1
NB = (N * OUT_W) // MEM_DW
BB = (N * BIAS_W) // MEM_DW
CLK_NS = 10
CLK_MHZ = 1000.0 / CLK_NS

WBUF_DEPTH = 256
ABUF_DEPTH = 256
RBUF_DEPTH = 512

# APB map: paddr[14:13] picks CSR / WBUF / ABUF / RBUF, word index = paddr[12:3]
WIN_WBUF = 0x2000
WIN_ABUF = 0x4000
WIN_RBUF = 0x6000
CSR_SPAN = 0x40

REG_COMMAND = 0x00
REG_STATUS = 0x04
REG_INT_ENABLE = 0x08
REG_POSTPROC_CFG = 0x0C
REG_POSTPROC_MULT = 0x10
REG_POSTPROC_SHIFT = 0x14
REG_WEIGHT_ADDR = 0x18
REG_ACT_ADDR = 0x1C
REG_ACT_COUNT = 0x20
REG_DST_ADDR = 0x24

CMD_LOAD_W = 1 << 0
CMD_START = 1 << 1
CMD_ABORT = 1 << 2

STATUS_BUSY = 1 << 0
STATUS_W_VALID = 1 << 1
STATUS_DONE = 1 << 2
STATUS_CMD_ERR = 1 << 3
STATUS_CFG_ERR = 1 << 4
STATUS_ERR = STATUS_CMD_ERR | STATUS_CFG_ERR

IE_DONE = 1 << 0
IE_ERR = 1 << 1

CFG_RELU = 1 << 0
CFG_REQUANT = 1 << 1

TIMEOUT_LOAD = 500
TIMEOUT_RUN = 5000


def clamp(value, width):
    return min(max(value, -(1 << (width - 1))), (1 << (width - 1)) - 1)


def expected_row(activation, weights, biases):
    return [
        wrap_signed(biases[col] + sum(activation[row] * weights[row][col] for row in range(N)), ACC_W)
        for col in range(N)
    ]


def expected_quant_row(activation, weights, biases, mult, shift, relu):
    lanes = []
    for acc in expected_row(activation, weights, biases):
        value = max(acc, 0) if relu else acc
        lanes.append(clamp((value * mult + ((1 << shift) >> 1)) >> shift, Q_W))
    return lanes


def pack_bias_beats(biases):
    flat = pack_signed_lanes(biases, BIAS_W)
    return [(flat >> (beat * MEM_DW)) & BEAT_MASK for beat in range(BB)]


def unpack_result_beats(beats):
    flat = 0
    for beat, value in enumerate(beats):
        flat |= (int(value) & BEAT_MASK) << (beat * MEM_DW)
    return unpack_signed_lanes(flat, N, OUT_W)


class Metrics:
    def __init__(self):
        self.total = 0
        self.busy = 0
        self.load = 0
        self.run = 0
        self.act_rows = 0

    def snapshot(self):
        macs = self.act_rows * N * N
        run_s = self.run * (CLK_NS * 1e-9)
        return {
            "cycles_total": self.total,
            "cycles_busy": self.busy,
            "cycles_load": self.load,
            "cycles_run": self.run,
            "act_rows": self.act_rows,
            "macs": macs,
            "throughput_rows_per_cycle": (self.act_rows / self.run) if self.run else 0.0,
            "busy_fraction": (self.busy / self.total) if self.total else 0.0,
            "mops": (macs / run_s / 1e6) if run_s else 0.0,
            "clk_mhz": CLK_MHZ,
        }

    def report(self, dut, label):
        snap = self.snapshot()
        dut._log.info(
            "%s metrics: load=%d run=%d busy=%d rows=%d thr=%.3f row/cyc mops=%.1f busy%%=%.1f",
            label,
            snap["cycles_load"],
            snap["cycles_run"],
            snap["cycles_busy"],
            snap["act_rows"],
            snap["throughput_rows_per_cycle"],
            snap["mops"],
            100.0 * snap["busy_fraction"],
        )
        return snap


_clock_task = None


async def cycle(dut):
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def reset_dut(dut):
    global _clock_task
    if _clock_task is not None and not _clock_task.done():
        _clock_task.cancel()
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    dut.s_apb_psel.value = 0
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0
    dut.s_apb_pprot.value = 0
    dut.s_apb_paddr.value = 0
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0
    _clock_task = cocotb.start_soon(Clock(dut.i_clk, CLK_NS, unit="ns").start())
    await Timer(3 * CLK_NS, unit="ns")
    dut.i_rstn.value = 1
    await cycle(dut)
    await cycle(dut)


async def apb_write(dut, addr, data, strb=0xF, expect_err=False):
    await RisingEdge(dut.i_clk)
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 1
    dut.s_apb_pprot.value = 0
    dut.s_apb_paddr.value = addr & 0x7FFF
    dut.s_apb_pwdata.value = data & 0xFFFFFFFF
    dut.s_apb_pstrb.value = strb & 0xF
    await RisingEdge(dut.i_clk)
    dut.s_apb_penable.value = 1
    for _ in range(16):
        await Timer(1, unit="ns")
        if int(dut.s_apb_pready.value):
            assert int(dut.s_apb_pslverr.value) == int(expect_err), f"APB write @0x{addr:04x} pslverr"
            await RisingEdge(dut.i_clk)
            dut.s_apb_psel.value = 0
            dut.s_apb_penable.value = 0
            dut.s_apb_pwrite.value = 0
            dut.s_apb_pstrb.value = 0
            return
        await RisingEdge(dut.i_clk)
    raise AssertionError(f"APB write timeout @0x{addr:04x}")


async def apb_read(dut, addr, expect_err=False):
    await RisingEdge(dut.i_clk)
    dut.s_apb_psel.value = 1
    dut.s_apb_penable.value = 0
    dut.s_apb_pwrite.value = 0
    dut.s_apb_pprot.value = 0
    dut.s_apb_paddr.value = addr & 0x7FFF
    dut.s_apb_pwdata.value = 0
    dut.s_apb_pstrb.value = 0
    await RisingEdge(dut.i_clk)
    dut.s_apb_penable.value = 1
    for _ in range(16):
        await Timer(1, unit="ns")
        if int(dut.s_apb_pready.value):
            data = int(dut.s_apb_prdata.value)
            assert int(dut.s_apb_pslverr.value) == int(expect_err), f"APB read @0x{addr:04x} pslverr"
            await RisingEdge(dut.i_clk)
            dut.s_apb_psel.value = 0
            dut.s_apb_penable.value = 0
            return data
        await RisingEdge(dut.i_clk)
    raise AssertionError(f"APB read timeout @0x{addr:04x}")


async def win_write_beat(dut, base, beat, data):
    addr = base + beat * BEAT_BYTES
    await apb_write(dut, addr, data & 0xFFFFFFFF)
    await apb_write(dut, addr + 4, (data >> 32) & 0xFFFFFFFF)


async def win_read_beat(dut, base, beat):
    addr = base + beat * BEAT_BYTES
    lo = await apb_read(dut, addr)
    hi = await apb_read(dut, addr + 4)
    return lo | (hi << 32)


async def wait_status(dut, mask, expect, limit, label):
    for _ in range(limit):
        status = await apb_read(dut, REG_STATUS)
        if ((status & mask) != 0) == bool(expect):
            return status
        await cycle(dut)
    raise AssertionError(f"Timeout waiting for STATUS.{label}={int(expect)}")


def _hier_bit(dut, *path):
    node = dut
    try:
        for part in path:
            node = getattr(node, part)
        return int(node.value)
    except AttributeError:
        return None


async def tick_metrics(dut, metrics, phase=None):
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    metrics.total += 1
    if phase == "load":
        metrics.load += 1
    elif phase == "run":
        metrics.run += 1

    # Live status from the hierarchy when it is visible (RTL / hierarchical netlist); else skip.
    busy = _hier_bit(dut, "u_sys", "busy")
    if busy:
        metrics.busy += 1


def make_case(seed, act_count, lo=-8, hi=8):
    rng = random.Random(seed)
    weights = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(N)]
    biases = [rng.randint(-64, 64) for _ in range(N)]
    activations = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(act_count)]
    return weights, biases, activations


async def load_weight_block(dut, w_beat, weights, biases):
    beats = pack_bias_beats(biases) + [pack_signed_lanes(row, DW) for row in weights]
    for offset, beat in enumerate(beats):
        await win_write_beat(dut, WIN_WBUF, w_beat + offset, beat)


async def load_activations(dut, a_beat, activations):
    for offset, row in enumerate(activations):
        await win_write_beat(dut, WIN_ABUF, a_beat + offset, pack_signed_lanes(row, DW))


async def read_results(dut, dst, count, quant):
    rows = []
    for index in range(count):
        if quant:
            beat = await win_read_beat(dut, WIN_RBUF, dst + index)
            rows.append(unpack_signed_lanes(beat, N, Q_W))
        else:
            beats = [await win_read_beat(dut, WIN_RBUF, dst + index * NB + k) for k in range(NB)]
            rows.append(unpack_result_beats(beats))
    return rows


def expected_rows(activations, weights, biases, quant, relu, mult, shift):
    if quant:
        return [expected_quant_row(a, weights, biases, mult, shift, relu) for a in activations]
    return [expected_row(a, weights, biases) for a in activations]


async def configure_layer(dut, act_count, w_beat=0, a_beat=0, dst=0, quant=0, relu=0, mult=1, shift=0, ie=IE_DONE):
    cfg = (CFG_RELU if relu else 0) | (CFG_REQUANT if quant else 0)
    await apb_write(dut, REG_POSTPROC_CFG, cfg)
    await apb_write(dut, REG_POSTPROC_MULT, mult)
    await apb_write(dut, REG_POSTPROC_SHIFT, shift)
    await apb_write(dut, REG_WEIGHT_ADDR, w_beat)
    await apb_write(dut, REG_ACT_ADDR, a_beat)
    await apb_write(dut, REG_ACT_COUNT, act_count)
    await apb_write(dut, REG_DST_ADDR, dst)
    await apb_write(dut, REG_INT_ENABLE, ie)


async def load_weights_cmd(dut, metrics=None):
    await apb_write(dut, REG_COMMAND, CMD_LOAD_W)
    for cycle_i in range(TIMEOUT_LOAD):
        if metrics is not None:
            await tick_metrics(dut, metrics, phase="load")
        else:
            await cycle(dut)
        if cycle_i % 4 == 0:
            status = await apb_read(dut, REG_STATUS)
            if (status & STATUS_BUSY) == 0 and (status & STATUS_W_VALID):
                assert (status & STATUS_ERR) == 0, f"STATUS after load: 0x{status:x}"
                return
    raise AssertionError("LOAD_W did not complete")


async def start_and_wait_done(dut, metrics=None):
    await apb_write(dut, REG_COMMAND, CMD_START)
    for _ in range(TIMEOUT_RUN):
        if metrics is not None:
            await tick_metrics(dut, metrics, phase="run")
        else:
            await cycle(dut)
        if int(dut.o_irq.value):
            break
    else:
        raise AssertionError("START did not reach DONE (irq)")

    status = await apb_read(dut, REG_STATUS)
    assert status & STATUS_DONE, f"IRQ without DONE, STATUS=0x{status:x}"
    assert (status & STATUS_ERR) == 0, f"STATUS after run: 0x{status:x}"
    # BUSY is a registered copy of the sequencer state, give it a few cycles to fall
    await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")


async def clear_done(dut):
    await apb_write(dut, REG_STATUS, STATUS_DONE)
    status = await apb_read(dut, REG_STATUS)
    assert (status & STATUS_DONE) == 0
    assert int(dut.o_irq.value) == 0


async def run_gemm(dut, seed, act_count, label, quant=0, relu=0, mult=1, shift=0, w_beat=0, a_beat=0, dst=0):
    await reset_dut(dut)
    weights, biases, activations = make_case(seed, act_count)
    await load_weight_block(dut, w_beat, weights, biases)
    await load_activations(dut, a_beat, activations)
    await configure_layer(dut, act_count, w_beat, a_beat, dst, quant, relu, mult, shift)

    metrics = Metrics()
    metrics.act_rows = act_count

    await load_weights_cmd(dut, metrics)
    await start_and_wait_done(dut, metrics)

    expected = expected_rows(activations, weights, biases, quant, relu, mult, shift)
    actual = await read_results(dut, dst, act_count, quant)
    assert actual == expected, f"GEMM mismatch:\n expected={expected}\n actual={actual}"

    await clear_done(dut)

    snap = metrics.report(dut, label)
    snap["read_beats"] = BB + N + act_count
    snap["write_beats"] = act_count * (1 if quant else NB)
    dut._log.info(
        "%s traffic: read_beats=%d (bias+wt+act) write_beats=%d load_cycles=%d run_cycles=%d",
        label,
        snap["read_beats"],
        snap["write_beats"],
        snap["cycles_load"],
        snap["cycles_run"],
    )
    return snap, weights, biases, activations


@cocotb.test()
async def test_csr_reset_and_readback(dut):
    await reset_dut(dut)
    status = await apb_read(dut, REG_STATUS)
    assert status == 0, f"STATUS after reset: 0x{status:x}"
    assert int(dut.o_irq.value) == 0

    # field widths are enforced by the CSR: write all ones, read back the field mask
    for reg, mask in (
        (REG_INT_ENABLE, 0x3),
        (REG_POSTPROC_CFG, 0x3),
        (REG_POSTPROC_MULT, 0x7FFF),
        (REG_POSTPROC_SHIFT, 0x3F),
        (REG_WEIGHT_ADDR, 0xFF),
        (REG_ACT_ADDR, 0xFF),
        (REG_ACT_COUNT, 0x1FF),
        (REG_DST_ADDR, 0x1FF),
    ):
        await apb_write(dut, reg, 0xFFFFFFFF)
        assert await apb_read(dut, reg) == mask, f"reg 0x{reg:02x}"
        await apb_write(dut, reg, 0)
        assert await apb_read(dut, reg) == 0, f"reg 0x{reg:02x}"

    # START without weights is an illegal sequence; the flag is sticky and W1C
    await apb_write(dut, REG_ACT_COUNT, 1)
    await apb_write(dut, REG_COMMAND, CMD_START)
    await cycle(dut)
    status = await apb_read(dut, REG_STATUS)
    assert status & STATUS_CMD_ERR, "START without weights should set CMD_ERR"
    assert (status & STATUS_BUSY) == 0
    assert int(dut.o_irq.value) == 0, "ERR_IE is off"
    await apb_write(dut, REG_STATUS, STATUS_ERR)
    assert (await apb_read(dut, REG_STATUS)) & STATUS_ERR == 0


@cocotb.test()
async def test_window_rw_and_errors(dut):
    await reset_dut(dut)

    for base, depth in ((WIN_WBUF, WBUF_DEPTH), (WIN_ABUF, ABUF_DEPTH), (WIN_RBUF, RBUF_DEPTH)):
        first, last = 0, depth - 1
        await win_write_beat(dut, base, first, 0x0123456789ABCDEF)
        await win_write_beat(dut, base, last, 0xFEDCBA9876543210)
        assert await win_read_beat(dut, base, first) == 0x0123456789ABCDEF
        assert await win_read_beat(dut, base, last) == 0xFEDCBA9876543210

        # byte strobes: only bytes 0 and 2 of the low half change, high half untouched
        await apb_write(dut, base + 0x10, 0xFFFFFFFF)
        await apb_write(dut, base + 0x14, 0xCAFEF00D)
        await apb_write(dut, base + 0x10, 0x00112233, strb=0b0101)
        assert await apb_read(dut, base + 0x10) == 0xFF11FF33
        assert await apb_read(dut, base + 0x14) == 0xCAFEF00D

    # past the end of a buffer, and CSR space beyond the register block (no aliasing)
    await apb_read(dut, WIN_WBUF + WBUF_DEPTH * BEAT_BYTES, expect_err=True)
    await apb_write(dut, WIN_ABUF + ABUF_DEPTH * BEAT_BYTES, 0, expect_err=True)
    await apb_read(dut, WIN_RBUF + RBUF_DEPTH * BEAT_BYTES, expect_err=True)
    await apb_write(dut, CSR_SPAN + REG_ACT_COUNT, 5, expect_err=True)
    assert await apb_read(dut, REG_ACT_COUNT) == 0, "write above the CSR block must not alias"


@cocotb.test()
async def test_io_single_row(dut):
    snap, *_ = await run_gemm(dut, seed=11, act_count=1, label="single")
    assert snap["cycles_load"] > 0
    assert snap["cycles_run"] > 0


@cocotb.test()
async def test_io_stream_and_throughput_raw(dut):
    act_count = 32
    snap, *_ = await run_gemm(dut, seed=22, act_count=act_count, label="raw32")
    assert snap["act_rows"] == act_count
    assert snap["macs"] == act_count * N * N
    # raw rows need NB write beats each: ~1/NB row/cycle plus pipeline fill
    assert snap["throughput_rows_per_cycle"] > 0.15
    assert snap["mops"] > 0.0


@cocotb.test()
async def test_io_stream_and_throughput_requant(dut):
    act_count = 32
    snap, *_ = await run_gemm(
        dut, seed=33, act_count=act_count, label="requant32", quant=1, relu=1, mult=100, shift=9
    )
    # one write beat per row: the stream runs at ~1 row/cycle plus pipeline fill
    assert snap["throughput_rows_per_cycle"] > 0.4


@cocotb.test()
async def test_requant_full_abuf(dut):
    await run_gemm(dut, seed=44, act_count=ABUF_DEPTH, label="requant256", quant=1, relu=0, mult=0x1234, shift=11)


@cocotb.test()
async def test_nonzero_buffer_offsets(dut):
    await run_gemm(dut, seed=55, act_count=3, label="offsets", w_beat=17, a_beat=40, dst=100)
    await run_gemm(dut, seed=56, act_count=5, label="offsets_quant", quant=1, mult=77, shift=6, w_beat=240, a_beat=251, dst=500)


@cocotb.test()
async def test_cfg_errors_do_not_start(dut):
    await reset_dut(dut)
    weights, biases, activations = make_case(66, 2)
    await load_weight_block(dut, 0, weights, biases)
    await load_activations(dut, 0, activations)
    await configure_layer(dut, 2, ie=IE_DONE | IE_ERR)
    await load_weights_cmd(dut)

    async def expect_cfg_err(label):
        await apb_write(dut, REG_COMMAND, CMD_START)
        await cycle(dut)
        status = await apb_read(dut, REG_STATUS)
        assert status & STATUS_CFG_ERR, f"{label}: expected CFG_ERR, STATUS=0x{status:x}"
        assert (status & (STATUS_BUSY | STATUS_DONE | STATUS_CMD_ERR)) == 0, f"{label}: STATUS=0x{status:x}"
        assert int(dut.o_irq.value) == 1, f"{label}: ERR_IE should raise irq"
        await apb_write(dut, REG_STATUS, STATUS_ERR)
        await cycle(dut)
        assert int(dut.o_irq.value) == 0

    await apb_write(dut, REG_ACT_COUNT, 0)
    await expect_cfg_err("count 0")

    await apb_write(dut, REG_ACT_COUNT, 129)  # raw: 129 rows * NB beats > RBUF
    await expect_cfg_err("raw RBUF overrun")

    await apb_write(dut, REG_ACT_COUNT, 2)
    await apb_write(dut, REG_ACT_ADDR, ABUF_DEPTH - 1)  # ABUF overrun
    await expect_cfg_err("ABUF overrun")

    await apb_write(dut, REG_ACT_ADDR, 0)
    await apb_write(dut, REG_WEIGHT_ADDR, WBUF_DEPTH - (BB + N) + 1)  # weight block overrun
    await apb_write(dut, REG_COMMAND, CMD_LOAD_W)
    await cycle(dut)
    status = await apb_read(dut, REG_STATUS)
    assert status & STATUS_CFG_ERR and (status & STATUS_BUSY) == 0
    assert status & STATUS_W_VALID, "a rejected LOAD_W must not drop the resident weights"
    await apb_write(dut, REG_STATUS, STATUS_ERR)


@cocotb.test()
async def test_busy_blocks_window_and_locks_config(dut):
    await reset_dut(dut)
    act_count = 32
    weights, biases, activations = make_case(77, act_count)
    await load_weight_block(dut, 0, weights, biases)
    await load_activations(dut, 0, activations)
    await configure_layer(dut, act_count, mult=3, shift=1)
    await load_weights_cmd(dut)

    await apb_write(dut, REG_COMMAND, CMD_START)
    await wait_status(dut, STATUS_BUSY, True, 16, "BUSY")

    # the sequencer owns the SRAMs while busy
    await apb_read(dut, WIN_WBUF, expect_err=True)
    await apb_write(dut, WIN_ABUF, 0xDEADBEEF, expect_err=True)
    # datapath config is write-locked
    await apb_write(dut, REG_POSTPROC_MULT, 0x55)
    await apb_write(dut, REG_POSTPROC_CFG, CFG_REQUANT)
    assert await apb_read(dut, REG_POSTPROC_MULT) == 3
    assert await apb_read(dut, REG_POSTPROC_CFG) == 0
    status = await apb_read(dut, REG_STATUS)
    assert status & STATUS_BUSY, "run finished before the lock checks, make it longer"

    await wait_status(dut, STATUS_DONE, True, TIMEOUT_RUN, "DONE")
    await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")

    # the run used the original config, and everything unlocks afterwards
    actual = await read_results(dut, 0, act_count, quant=0)
    assert actual == expected_rows(activations, weights, biases, 0, 0, 3, 1)
    await apb_write(dut, REG_POSTPROC_MULT, 0x55)
    assert await apb_read(dut, REG_POSTPROC_MULT) == 0x55


@cocotb.test()
async def test_abort_keeps_weights_and_next_run_is_clean(dut):
    await reset_dut(dut)
    act_count = 64
    weights, biases, activations = make_case(88, act_count)
    await load_weight_block(dut, 0, weights, biases)
    await load_activations(dut, 0, activations)
    await configure_layer(dut, act_count)
    await load_weights_cmd(dut)

    await apb_write(dut, REG_COMMAND, CMD_START)
    await wait_status(dut, STATUS_BUSY, True, 16, "BUSY")
    await apb_write(dut, REG_COMMAND, CMD_ABORT)
    status = await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")
    assert status & STATUS_W_VALID, "ABORT during a run keeps the weights"
    assert (status & (STATUS_DONE | STATUS_ERR)) == 0

    # config is unlocked again; a shorter run on the same weights must come out right
    await apb_write(dut, REG_ACT_COUNT, 4)
    await start_and_wait_done(dut)
    actual = await read_results(dut, 0, 4, quant=0)
    assert actual == expected_rows(activations[:4], weights, biases, 0, 0, 1, 0)
    await clear_done(dut)

    # ABORT during a weight load leaves no weights behind
    await apb_write(dut, REG_COMMAND, CMD_LOAD_W)
    await apb_write(dut, REG_COMMAND, CMD_ABORT)
    status = await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")
    assert (status & STATUS_W_VALID) == 0, "a cut-short load must clear W_VALID"
    assert (status & STATUS_ERR) == 0

    # and START now is an illegal sequence
    await apb_write(dut, REG_COMMAND, CMD_START)
    await cycle(dut)
    assert (await apb_read(dut, REG_STATUS)) & STATUS_CMD_ERR


@cocotb.test()
async def test_irq_gating_and_done_clears_on_start(dut):
    await reset_dut(dut)
    weights, biases, activations = make_case(99, 3)
    await load_weight_block(dut, 0, weights, biases)
    await load_activations(dut, 0, activations)
    await configure_layer(dut, 3, ie=0)
    await load_weights_cmd(dut)

    await apb_write(dut, REG_COMMAND, CMD_START)
    await wait_status(dut, STATUS_DONE, True, TIMEOUT_RUN, "DONE")
    assert int(dut.o_irq.value) == 0, "DONE_IE is off"
    await apb_write(dut, REG_INT_ENABLE, IE_DONE)
    await Timer(1, unit="ns")
    assert int(dut.o_irq.value) == 1
    await apb_write(dut, REG_INT_ENABLE, IE_ERR)
    await Timer(1, unit="ns")
    assert int(dut.o_irq.value) == 0, "ERR_IE does not cover DONE"
    await apb_write(dut, REG_INT_ENABLE, IE_DONE)
    await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")

    # a new accepted START clears the sticky DONE by itself, no W1C needed
    await apb_write(dut, REG_COMMAND, CMD_START)
    await cycle(dut)
    status = await apb_read(dut, REG_STATUS)
    assert (status & STATUS_DONE) == 0, "an accepted START clears the previous DONE"
    await wait_status(dut, STATUS_DONE, True, TIMEOUT_RUN, "DONE")
    await wait_status(dut, STATUS_BUSY, False, 32, "BUSY")
    await clear_done(dut)


@cocotb.test()
async def test_mode_switch_without_reloading_weights(dut):
    await reset_dut(dut)
    act_count = 6
    weights, biases, activations = make_case(111, act_count)
    await load_weight_block(dut, 0, weights, biases)
    await load_activations(dut, 0, activations)
    await configure_layer(dut, act_count, dst=0)
    await load_weights_cmd(dut)

    await start_and_wait_done(dut)
    actual = await read_results(dut, 0, act_count, quant=0)
    assert actual == expected_rows(activations, weights, biases, 0, 0, 1, 0)
    await clear_done(dut)

    mult, shift = 77, 6
    await apb_write(dut, REG_POSTPROC_CFG, CFG_REQUANT | CFG_RELU)
    await apb_write(dut, REG_POSTPROC_MULT, mult)
    await apb_write(dut, REG_POSTPROC_SHIFT, shift)
    await apb_write(dut, REG_DST_ADDR, 200)
    await start_and_wait_done(dut)
    actual = await read_results(dut, 200, act_count, quant=1)
    assert actual == expected_rows(activations, weights, biases, 1, 1, mult, shift)
    await clear_done(dut)
    