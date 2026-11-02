import random

import cocotb
from cocotb.triggers import Timer

from helper.generic import pack_signed_lanes, pulse_clock

N = 8
OUT_W = 32
Q_W = 8
BIAS_W = 16
MEM_DW = 64
BEAT_MASK = (1 << MEM_DW) - 1
BB = (N * BIAS_W) // MEM_DW
LD_BEATS = BB + N
NB = (N * OUT_W) // MEM_DW
W_DEPTH = 256
A_DEPTH = 256
R_DEPTH = 512
TIMEOUT = 2000

SIGNALS = {
    "busy": "o_busy",
    "w_valid": "o_w_valid",
    "done": "o_done",
    "start_acc": "o_start_acc",
    "err_cmd": "o_err_cmd",
    "err_cfg": "o_err_cfg",
    "w_ce": "o_w_ce",
    "w_addr": "o_w_addr",
    "a_ce": "o_a_ce",
    "a_addr": "o_a_addr",
    "r_ce": "o_r_ce",
    "r_addr": "o_r_addr",
    "r_wdata": "o_r_wdata",
    "bias_shift": "o_bias_shift",
    "w_shift": "o_w_shift",
    "a_vld": "o_a_vld",
    "a_last": "o_a_last",
    "flush": "o_flush",
}


def snapshot(dut):
    return {key: int(getattr(dut, name).value) for key, name in SIGNALS.items()}


async def cycle(dut):
    # inputs are already driven; sample this cycle, then clock it
    await Timer(1, unit="ns")
    snap = snapshot(dut)
    await pulse_clock(dut.i_clk)
    return snap


async def reset_dut(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0

    defaults = {
        "i_load_w": 0,
        "i_start": 0,
        "i_abort": 0,
        "i_quant_en": 0,
        "i_w_addr": 0,
        "i_a_addr": 0,
        "i_a_count": 1,
        "i_r_addr": 0,
        "i_c_vld": 0,
        "i_c_last": 0,
        "i_c_data": 0,
    }
    for name, value in defaults.items():
        getattr(dut, name).value = value

    for _ in range(3):
        await pulse_clock(dut.i_clk)

    dut.i_rstn.value = 1
    await cycle(dut)


async def command(dut, *signals):
    # one-cycle command pulse; the returned snapshot is the cycle it was applied in
    for name in signals:
        getattr(dut, name).value = 1
    snap = await cycle(dut)
    for name in signals:
        getattr(dut, name).value = 0
    return snap


async def trace_until_idle(dut, limit=TIMEOUT):
    trace = []
    for _ in range(limit):
        snap = await cycle(dut)
        trace.append(snap)
        if not snap["busy"]:
            return trace
    raise AssertionError("Sequencer did not return to idle")


async def load_block(dut, w_addr=0):
    dut.i_w_addr.value = w_addr
    snap = await command(dut, "i_load_w")
    assert snap["err_cmd"] == 0 and snap["err_cfg"] == 0
    return await trace_until_idle(dut)


async def run_job(dut, rows, a_addr, r_addr, quant, spacing, delay):
    """START a job and play the core: row k is presented to i_c_* at trace
    index delay + k*spacing (index 0 = first cycle after the command)."""
    count = len(rows)
    dut.i_quant_en.value = quant
    dut.i_a_addr.value = a_addr
    dut.i_a_count.value = count
    dut.i_r_addr.value = r_addr
    snap = await command(dut, "i_start")
    assert snap["start_acc"] == 1 and snap["err_cmd"] == 0 and snap["err_cfg"] == 0

    schedule = {delay + k * spacing: k for k in range(count)}
    last_index = delay + (count - 1) * spacing
    trace = []
    for index in range(TIMEOUT):
        k = schedule.get(index)
        dut.i_c_vld.value = int(k is not None)
        dut.i_c_last.value = int(k == count - 1)
        dut.i_c_data.value = rows[k] if k is not None else 0
        snap = await cycle(dut)
        trace.append(snap)
        if index > last_index and not snap["busy"]:
            break
    else:
        raise AssertionError("Job did not return to idle")

    dut.i_c_vld.value = 0
    dut.i_c_last.value = 0
    dut.i_c_data.value = 0
    return trace


def where(trace, key):
    return [index for index, snap in enumerate(trace) if snap[key]]


def quant_rows(rng, count):
    lanes = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(count)]
    rows = [pack_signed_lanes(row, OUT_W) for row in lanes]  # sign-extended int8, like postproc
    beats = [pack_signed_lanes(row, Q_W) for row in lanes]
    return rows, beats


def raw_rows(rng, count):
    rows = [rng.getrandbits(N * OUT_W) for _ in range(count)]
    beats = [(row >> (beat * MEM_DW)) & BEAT_MASK for row in rows for beat in range(NB)]
    return rows, beats


def check_writes(trace, first, beats, r_addr):
    writes = where(trace, "r_ce")
    assert writes == list(range(first, first + len(beats))), f"write cycles {writes}"
    assert [trace[i]["r_addr"] for i in writes] == [r_addr + i for i in range(len(beats))]
    assert [trace[i]["r_wdata"] for i in writes] == beats
    assert where(trace, "done") == [writes[-1]], "DONE must pulse once, on the last write"
    assert trace[writes[-1]]["busy"] == 1
    assert trace[-1]["busy"] == 0 and len(trace) == writes[-1] + 2


@cocotb.test()
async def test_load_sequence(dut):
    await reset_dut(dut)
    trace = await load_block(dut, w_addr=5)

    reads = where(trace, "w_ce")
    assert reads == list(range(LD_BEATS)), "one WBUF read per cycle, starting right after the command"
    assert [trace[i]["w_addr"] for i in reads] == [5 + i for i in range(LD_BEATS)]
    # flags are registered with the issue, so they line up with the SRAM data one cycle later
    assert where(trace, "bias_shift") == [r + 1 for r in reads[:BB]]
    assert where(trace, "w_shift") == [r + 1 for r in reads[BB:]]
    assert where(trace, "a_ce") == [] and where(trace, "r_ce") == []

    final = reads[-1] + 2
    assert len(trace) == final + 1
    assert trace[final - 1]["busy"] == 1 and trace[final - 1]["w_valid"] == 0
    assert trace[final]["busy"] == 0 and trace[final]["w_valid"] == 1


@cocotb.test()
async def test_run_requant_one_beat_per_row(dut):
    await reset_dut(dut)
    await load_block(dut)
    rng = random.Random(1)
    rows, beats = quant_rows(rng, 5)

    trace = await run_job(dut, rows, a_addr=3, r_addr=20, quant=1, spacing=1, delay=8)

    # rows are issued every cycle, tagged one cycle later
    assert where(trace, "a_ce") == [0, 1, 2, 3, 4]
    assert [trace[i]["a_addr"] for i in range(5)] == [3, 4, 5, 6, 7]
    assert where(trace, "a_vld") == [1, 2, 3, 4, 5]
    assert where(trace, "a_last") == [5]
    # one write beat per row, the cycle after the row was handed over
    check_writes(trace, 9, beats, 20)


@cocotb.test()
async def test_run_raw_paced_four_beats_per_row(dut):
    await reset_dut(dut)
    await load_block(dut)
    rng = random.Random(2)
    rows, beats = raw_rows(rng, 3)

    trace = await run_job(dut, rows, a_addr=7, r_addr=8, quant=0, spacing=NB, delay=12)

    # raw rows are issued every NB cycles so the 4-beat writer never overruns
    assert where(trace, "a_ce") == [0, NB, 2 * NB]
    assert [trace[i]["a_addr"] for i in (0, NB, 2 * NB)] == [7, 8, 9]
    assert where(trace, "a_vld") == [1, NB + 1, 2 * NB + 1]
    assert where(trace, "a_last") == [2 * NB + 1]
    # row k is written as NB consecutive beats; lanes 2j,2j+1 sit in beat j
    check_writes(trace, 13, beats, 8)


@cocotb.test()
async def test_back_to_back_runs_and_mode_change(dut):
    await reset_dut(dut)
    await load_block(dut)
    rng = random.Random(3)

    rows, beats = raw_rows(rng, 2)
    trace = await run_job(dut, rows, a_addr=0, r_addr=0, quant=0, spacing=NB, delay=6)
    check_writes(trace, 7, beats, 0)

    rows, beats = quant_rows(rng, 3)
    trace = await run_job(dut, rows, a_addr=10, r_addr=40, quant=1, spacing=1, delay=6)
    assert where(trace, "a_ce") == [0, 1, 2], "pace must restart at 1 row/cycle after a raw run"
    check_writes(trace, 7, beats, 40)


@cocotb.test()
async def test_command_errors(dut):
    await reset_dut(dut)

    # START before any weights
    dut.i_a_count.value = 1
    snap = await command(dut, "i_start")
    assert (snap["err_cmd"], snap["err_cfg"], snap["start_acc"]) == (1, 0, 0)
    assert (await cycle(dut))["busy"] == 0

    # LOAD_W and START together
    snap = await command(dut, "i_load_w", "i_start")
    assert (snap["err_cmd"], snap["err_cfg"]) == (1, 0)
    assert (await cycle(dut))["busy"] == 0

    # weight block must fit WBUF: last legal start is W_DEPTH - LD_BEATS
    dut.i_w_addr.value = W_DEPTH - LD_BEATS + 1
    snap = await command(dut, "i_load_w")
    assert (snap["err_cmd"], snap["err_cfg"]) == (0, 1)
    assert (await cycle(dut))["busy"] == 0
    trace = await load_block(dut, w_addr=W_DEPTH - LD_BEATS)
    assert trace[-1]["w_valid"] == 1

    async def start_case(count, a_addr, r_addr, quant, ok):
        dut.i_a_count.value = count
        dut.i_a_addr.value = a_addr
        dut.i_r_addr.value = r_addr
        dut.i_quant_en.value = quant
        snap = await command(dut, "i_start")
        assert snap["err_cmd"] == 0
        assert snap["err_cfg"] == int(not ok), f"count={count} a={a_addr} r={r_addr} quant={quant}"
        assert snap["start_acc"] == int(ok)
        if ok:
            snap = await command(dut, "i_abort")
            assert snap["err_cmd"] == 0 and snap["err_cfg"] == 0
        assert (await cycle(dut))["busy"] == 0

    await start_case(0, 0, 0, 1, False)                     # empty run
    await start_case(2, A_DEPTH - 1, 0, 1, False)           # ABUF overrun
    await start_case(2, A_DEPTH - 2, 0, 1, True)            # ABUF exact fit
    await start_case(128, 0, 1, 0, False)                   # raw: 128 rows * 4 beats + 1 > RBUF
    await start_case(128, 0, 0, 0, True)                    # raw: exact fit
    await start_case(129, 0, 0, 0, False)
    await start_case(256, 0, 256, 1, True)                  # requant: 1 beat/row, exact fit
    await start_case(256, 0, 257, 1, False)

    # commands while busy are rejected, ABORT is always accepted
    dut.i_a_count.value = 4
    dut.i_quant_en.value = 1
    dut.i_r_addr.value = 0
    snap = await command(dut, "i_start")
    assert snap["start_acc"] == 1
    snap = await command(dut, "i_load_w")
    assert snap["err_cmd"] == 1
    snap = await command(dut, "i_start")
    assert snap["err_cmd"] == 1
    snap = await command(dut, "i_abort")
    assert (snap["err_cmd"], snap["err_cfg"], snap["flush"]) == (0, 0, 1)

    # ABORT while idle is harmless
    assert (await cycle(dut))["busy"] == 0
    snap = await command(dut, "i_abort")
    assert (snap["err_cmd"], snap["err_cfg"], snap["flush"]) == (0, 0, 1)
    snap = await cycle(dut)
    assert snap["busy"] == 0 and snap["w_valid"] == 1


@cocotb.test()
async def test_abort_during_load_clears_w_valid(dut):
    await reset_dut(dut)
    await load_block(dut)
    assert (await cycle(dut))["w_valid"] == 1

    dut.i_w_addr.value = 0
    await command(dut, "i_load_w")
    for _ in range(4):
        snap = await cycle(dut)
        assert snap["busy"] == 1 and snap["w_valid"] == 0

    snap = await command(dut, "i_abort")
    assert snap["flush"] == 1

    for _ in range(LD_BEATS + 2):
        snap = await cycle(dut)
        assert snap["busy"] == 0 and snap["w_valid"] == 0
        assert snap["w_ce"] == 0 and snap["bias_shift"] == 0 and snap["w_shift"] == 0


@cocotb.test()
async def test_abort_during_run_keeps_w_valid(dut):
    await reset_dut(dut)
    await load_block(dut)

    dut.i_quant_en.value = 1
    dut.i_a_count.value = 8
    dut.i_a_addr.value = 0
    dut.i_r_addr.value = 0
    await command(dut, "i_start")
    for _ in range(3):
        snap = await cycle(dut)
        assert snap["busy"] == 1

    snap = await command(dut, "i_abort")
    assert snap["flush"] == 1

    for _ in range(12):
        snap = await cycle(dut)
        assert snap["busy"] == 0 and snap["w_valid"] == 1
        assert snap["a_ce"] == 0 and snap["a_vld"] == 0 and snap["a_last"] == 0
        assert snap["r_ce"] == 0 and snap["done"] == 0

    # and the next run is clean
    rng = random.Random(4)
    rows, beats = quant_rows(rng, 2)
    trace = await run_job(dut, rows, a_addr=0, r_addr=5, quant=1, spacing=1, delay=6)
    check_writes(trace, 7, beats, 5)