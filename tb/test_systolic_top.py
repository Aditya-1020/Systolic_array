import os, random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

N, DW, OW, HALF = 8, 8, 32, 128

def pack(vals, bits):
    return sum((v & ((1 << bits) - 1)) << (i * bits) for i, v in enumerate(vals))

def unpack(word, n, bits):
    out = []
    for i in range(n):
        v = (word >> (i * bits)) & ((1 << bits) - 1)
        out.append(v - (1 << bits) if v >> (bits - 1) else v)
    return out

def rv():
    return random.choice([-128, 127, random.randint(-128, 127), random.randint(-128, 127)])

def ref_row(a, W, bias, shift, relu):
    row = []
    for c in range(N):
        acc = sum(a[r] * W[r][c] for r in range(N)) + bias[c]
        v = (acc + ((1 << (shift - 1)) if shift else 0)) >> shift
        if relu and v < 0:
            v = 0
        row.append(max(-128, min(127, v)))
    return row

class Env:
    def __init__(self, dut):
        self.d = dut
        self.items = []          # ("W", W) or ("A", frame)
        self.expected = []       # list of frames (list of rows) in result order
        self.p_gap = 0.3

    async def tick(self):
        await FallingEdge(self.d.i_clk)

    def idle_inputs(self):
        d = self.d
        for s in (d.i_host_w_en, d.i_act_push, d.i_host_r_en, d.i_res_pop,
                  d.i_cmd_load_w, d.i_cmd_start):
            s.value = 0
        for s in (d.i_host_w_addr, d.i_host_w_data, d.i_act_push_half, d.i_host_r_addr,
                  d.i_res_pop_half, d.i_w_base, d.i_a_base, d.i_count):
            s.value = 0

    async def reset(self):
        d = self.d
        cocotb.start_soon(Clock(d.i_clk, 10, "ns").start())
        self.idle_inputs()
        d.i_rstn.value = 0
        for _ in range(4):
            await self.tick()
        d.i_rstn.value = 1
        for _ in range(6):
            await self.tick()

    async def gap(self):
        while random.random() < self.p_gap:
            await self.tick()

    async def producer(self):
        d = self.d
        for k, (kind, data) in enumerate(self.items):
            h = k % 2
            while int(d.o_act_full.value) >> h & 1:
                await self.tick()
            words = data if kind == "W" else data
            for i, w in enumerate(words):
                await self.gap()
                d.i_host_w_en.value = 1
                d.i_host_w_addr.value = (h << 7) | i
                d.i_host_w_data.value = w
                await self.tick()
                d.i_host_w_en.value = 0
            d.i_act_push.value = 1
            d.i_act_push_half.value = h
            await self.tick()
            d.i_act_push.value = 0

    async def commander(self):
        d = self.d
        for k, (kind, data) in enumerate(self.items):
            h = k % 2
            await self.gap()
            while not int(d.o_cmd_ready.value):
                await self.tick()
            if kind == "W":
                d.i_cmd_load_w.value = 1
                d.i_w_base.value = h << 7
            else:
                d.i_cmd_start.value = 1
                d.i_a_base.value = h << 7
                d.i_count.value = len(data)
            await self.tick()
            d.i_cmd_load_w.value = 0
            d.i_cmd_start.value = 0

    async def consumer(self):
        d = self.d
        for f, frame in enumerate(self.expected):
            h = f % 2
            while not (int(d.o_res_full.value) >> h & 1):
                await self.tick()
            for _ in range(random.randint(0, 30)):   # let result halves back up -> stalls
                await self.tick()
            got = []
            pending = None
            for i in range(len(frame) + 1):
                if pending is not None:
                    assert int(d.o_host_r_valid.value) == 1, "r_valid missing"
                    got.append(unpack(int(d.o_host_r_data.value), N, DW))
                if i < len(frame):
                    await self.gap_r()
                    pending = i
                    d.i_host_r_en.value = 1
                    d.i_host_r_addr.value = (h << 7) | i
                else:
                    pending = None
                    d.i_host_r_en.value = 0
                await self.tick()
                d.i_host_r_en.value = 0
                if i == len(frame) - 1:
                    # last read issued; sample data one cycle later
                    assert int(d.o_host_r_valid.value) == 1
                    got.append(unpack(int(d.o_host_r_data.value), N, DW))
                    break
            # NOTE: simple model: read gaps would break pending logic, so gap_r() returns immediately
            assert got == frame, f"frame {f} mismatch\n got {got[:3]}...\n exp {frame[:3]}..."
            d.i_res_pop.value = 1
            d.i_res_pop_half.value = h
            await self.tick()
            d.i_res_pop.value = 0
            self.d._log.info(f"frame {f} ({len(frame)} rows) OK")

    async def gap_r(self):
        return

@cocotb.test()
async def end_to_end(dut):
    seed = int(os.getenv("SEED", random.randrange(1 << 30)))
    random.seed(seed)
    dut._log.info(f"SEED={seed}")
    env = Env(dut)
    await env.reset()
    shift = random.randint(0, 9)
    relu = random.randint(0, 1)
    bias = [random.randint(-5000, 5000) for _ in range(N)]
    dut.i_shift.value = shift
    dut.i_relu_en.value = relu
    dut.i_bias.value = pack(bias, OW)

    W = None
    for grp in range(3):
        W = [[rv() for _ in range(N)] for _ in range(N)]
        env.items.append(("W", [pack(W[r], DW) for r in range(N)]))
        for _ in range(random.randint(1, 4)):
            L = random.choice([1, 2, 3, 8, 17, 40, 128])
            fr = [[rv() for _ in range(N)] for _ in range(L)]
            env.items.append(("A", [pack(v, DW) for v in fr]))
            env.expected.append([ref_row(v, W, bias, shift, relu) for v in fr])
    cocotb.start_soon(env.producer())
    cocotb.start_soon(env.commander())
    await env.consumer()
    for _ in range(50):
        await env.tick()
    assert not int(dut.o_busy.value), "still busy"
