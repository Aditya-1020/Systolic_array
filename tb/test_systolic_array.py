import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

DW = 8

def pack(vals, bits):
    return sum((v & ((1 << bits) - 1)) << (i * bits) for i, v in enumerate(vals))


def unpack(word, n, bits):
    out = []
    for i in range(n):
        v = (word >> (i * bits)) & ((1 << bits) - 1)
        out.append(v - (1 << bits) if v >> (bits - 1) else v)
    return out


def rv():  # biased toward int8 corners
    return random.choice([-128, 127, random.randint(-128, 127), random.randint(-128, 127)])


class Tb:
    def __init__(self, dut, p_valid=0.7, p_ready=0.6):
        self.d, self.pv, self.pr = dut, p_valid, p_ready
        self.n = len(dut.s_axis_a_tdata) // DW
        self.ow = len(dut.m_axis_c_tdata) // self.n
        self.a, self.w, self.exp = [], [], []  # pending beats / expected results
        self.load = self.a_on = self.w_on = False
        self.held = self.first_a = self.first_m = self.last_m = None
        self.done = self.cyc = 0

    async def reset(self):
        d = self.d
        cocotb.start_soon(Clock(d.i_clk, 10, "ns").start())
        d.i_rstn.value = 0
        for s in (d.i_load_w, d.s_axis_w_tvalid, d.s_axis_w_tdata, d.s_axis_a_tvalid,
                  d.s_axis_a_tdata, d.s_axis_a_tlast, d.m_axis_c_tready):
            s.value = 0
        for _ in range(4):
            await RisingEdge(d.i_clk)
        d.i_rstn.value = 1
        for _ in range(6):  # let reset_sync release
            await RisingEdge(d.i_clk)

    async def step(self):
        """One clock. Drive at falling edge, sample the pre-rising-edge handshake."""
        d = self.d
        await FallingEdge(d.i_clk)
        self.a_on = bool(self.a) and (self.a_on or random.random() < self.pv)
        self.w_on = bool(self.w)
        d.i_load_w.value, self.load = int(self.load), False
        d.s_axis_w_tvalid.value = int(self.w_on)
        d.s_axis_a_tvalid.value = int(self.a_on)
        if self.w_on:
            d.s_axis_w_tdata.value = self.w[0]
        if self.a_on:
            d.s_axis_a_tdata.value = self.a[0][0]
            d.s_axis_a_tlast.value = self.a[0][1]
        m_ready = random.random() < self.pr
        d.m_axis_c_tready.value = int(m_ready)
        await Timer(1, "ns")
        self.cyc += 1

        if self.w_on and int(d.s_axis_w_tready.value):
            self.w.pop(0)
        if self.a_on and int(d.s_axis_a_tready.value):
            self.a.pop(0)
            self.a_on = False
            self.first_a = self.first_a or self.cyc

        m_valid = int(d.m_axis_c_tvalid.value)
        beat = (int(d.m_axis_c_tdata.value), int(d.m_axis_c_tlast.value))
        if self.held is not None:  # AXIS: a stalled beat must not change
            assert m_valid and beat == self.held, "output changed while stalled"
        self.held = beat if (m_valid and not m_ready) else None
        if m_valid and m_ready:
            assert self.exp, "unexpected output beat"
            lanes, last = self.exp.pop(0)
            got = unpack(beat[0], self.n, self.ow)
            assert got == lanes, f"cycle {self.cyc}: got {got} exp {lanes}"
            assert beat[1] == last, f"cycle {self.cyc}: tlast {beat[1]} exp {last}"
            self.first_m = self.first_m or self.cyc
            self.last_m = self.cyc
        self.done += int(d.o_done.value)
        await RisingEdge(d.i_clk)

    async def drain(self):
        for _ in range(20000):
            await self.step()
            if not (self.a or self.w or self.exp) and not int(self.d.o_busy.value):
                break
        else:
            assert False, "timeout"
        for _ in range(3):  # let o_done pulse show
            await self.step()


async def run_round(tb, lens):
    """New random weights, then one frame per entry of lens. Returns expected o_done count."""
    n = tb.n
    W = [[rv() for _ in range(n)] for _ in range(n)]
    tb.w = [pack(W[n - 1 - k], DW) for k in range(n)]  # beat 0 = row N-1
    tb.load = True
    await tb.drain()
    assert int(tb.d.o_weights_loaded.value) == 1
    for L in lens:
        for i in range(L):
            v, last = [rv() for _ in range(n)], int(i == L - 1)
            tb.a.append((pack(v, DW), last))
            tb.exp.append(([sum(v[r] * W[r][c] for r in range(n)) for c in range(n)], last))
    await tb.drain()
    return 1 + len(lens)


@cocotb.test()
async def random_traffic(dut):
    seed = int(os.getenv("SEED", random.randrange(1 << 30)))
    random.seed(seed)
    dut._log.info(f"SEED={seed}")
    tb = Tb(dut)
    await tb.reset()
    exp_done = 0
    for _ in range(4):  # 4 weight sets, includes reload
        exp_done += await run_round(tb, [random.randint(1, 24) for _ in range(random.randint(1, 3))])
    assert tb.done == exp_done, f"o_done pulses {tb.done} exp {exp_done}"


@cocotb.test()
async def full_rate(dut):
    """No gaps, no stalls: latency must be 2N, throughput 1 beat/cycle."""
    random.seed(7)
    tb = Tb(dut, p_valid=1.0, p_ready=1.0)
    await tb.reset()
    await run_round(tb, [32])
    assert tb.first_m - tb.first_a == 2 * tb.n, f"latency {tb.first_m - tb.first_a}"
    assert tb.last_m - tb.first_m == 31, "bubbles in output stream"