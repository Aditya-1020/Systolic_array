import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

MASK64 = (1 << 64) - 1


async def initialize(dut):
    cocotb.start_soon(Clock(dut.i_clk_a, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.i_clk_b, 14, unit="ns").start())

    for name in (
        "i_a_req", "i_a_we", "i_a_addr", "i_a_wdata", "i_a_wmask",
        "i_b_gnt", "i_b_rvalid", "i_b_rdata",
    ):
        getattr(dut, name).value = 0
    dut.i_rstn_a.value = 0
    dut.i_rstn_b.value = 0

    for _ in range(4):
        await RisingEdge(dut.i_clk_a)
        await RisingEdge(dut.i_clk_b)

    await FallingEdge(dut.i_clk_a)
    dut.i_rstn_a.value = 1
    await FallingEdge(dut.i_clk_b)
    dut.i_rstn_b.value = 1

    for _ in range(4):
        await RisingEdge(dut.i_clk_a)
        await RisingEdge(dut.i_clk_b)


async def submit_a_request(dut, *, we, addr, data, mask=MASK64, expect_gnt=True):
    await FallingEdge(dut.i_clk_a)
    dut.i_a_req.value = 1
    dut.i_a_we.value = we
    dut.i_a_addr.value = addr
    dut.i_a_wdata.value = data
    dut.i_a_wmask.value = mask
    await Timer(1, unit="ns")

    got_gnt = bool(int(dut.o_a_gnt.value))
    assert got_gnt == expect_gnt, (
        f"request addr={addr}: expected grant={expect_gnt}, got={got_gnt}"
    )

    await RisingEdge(dut.i_clk_a)
    await Timer(1, unit="ns")
    await FallingEdge(dut.i_clk_a)
    dut.i_a_req.value = 0
    await RisingEdge(dut.i_clk_a)
    await Timer(1, unit="ns")


async def take_b_request(dut, timeout=40):
    for _ in range(timeout):
        await FallingEdge(dut.i_clk_b)
        if int(dut.o_b_req.value):
            request = (
                int(dut.o_b_we.value),
                int(dut.o_b_addr.value),
                int(dut.o_b_wdata.value),
                int(dut.o_b_wmask.value),
            )
            dut.i_b_gnt.value = 1
            await RisingEdge(dut.i_clk_b)
            await Timer(1, unit="ns")
            dut.i_b_gnt.value = 0
            return request
        await RisingEdge(dut.i_clk_b)
    raise AssertionError("timed out waiting for memory-side request")


@cocotb.test()
async def test_mem_cdc_request_fifo_backpressure_and_order(dut):
    await initialize(dut)
    dut.i_b_gnt.value = 0

    expected = []
    for index in range(4):
        addr = index + 3
        data = 0x1000000000000000 + index
        expected.append((1, addr, data, MASK64))
        await submit_a_request(
            dut, we=1, addr=addr, data=data, expect_gnt=True
        )

    await submit_a_request(
        dut, we=1, addr=31, data=0xFFFFFFFFFFFFFFFF, expect_gnt=False
    )

    observed = []
    for _ in expected:
        observed.append(await take_b_request(dut))

    assert observed == expected, f"request order mismatch: expected={expected}, got={observed}"

    for _ in range(4):
        await RisingEdge(dut.i_clk_a)
        await Timer(1, unit="ns")
    await submit_a_request(
        dut, we=1, addr=31, data=0xFFFFFFFFFFFFFFFF, expect_gnt=True
    )


@cocotb.test()
async def test_mem_cdc_read_response_is_returned_once(dut):
    await initialize(dut)

    await submit_a_request(
        dut, we=0, addr=17, data=0, mask=0, expect_gnt=True
    )

    request = await take_b_request(dut)
    assert request == (0, 17, 0, 0), f"unexpected read request: {request}"

    response = 0xA55A1234DEADBEEF
    await FallingEdge(dut.i_clk_b)
    dut.i_b_rdata.value = response
    dut.i_b_rvalid.value = 1
    await RisingEdge(dut.i_clk_b)
    await Timer(1, unit="ns")
    dut.i_b_rvalid.value = 0

    received = False
    for _ in range(30):
        await RisingEdge(dut.i_clk_a)
        await Timer(1, unit="ns")
        if int(dut.o_a_rvalid.value):
            assert int(dut.o_a_rdata.value) == response
            received = True
            break

    assert received, "APB-side read response did not arrive"
    await RisingEdge(dut.i_clk_a)
    await Timer(1, unit="ns")
    assert int(dut.o_a_rvalid.value) == 0, "read response valid was not a one-cycle pulse"
