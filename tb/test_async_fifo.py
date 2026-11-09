import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


@cocotb.test()
async def test_async_fifo_full_empty_and_order(dut):
    cocotb.start_soon(Clock(dut.wr_clk, 10, unit="ns").start())
    cocotb.start_soon(Clock(dut.rd_clk, 14, unit="ns").start())

    dut.wr_rstn.value = 0
    dut.rd_rstn.value = 0
    dut.wr_en.value = 0
    dut.wr_data.value = 0
    dut.rd_en.value = 0

    for _ in range(4):
        await RisingEdge(dut.wr_clk)
        await RisingEdge(dut.rd_clk)

    dut.wr_rstn.value = 1
    dut.rd_rstn.value = 1

    for _ in range(3):
        await RisingEdge(dut.wr_clk)
        await RisingEdge(dut.rd_clk)
    assert int(dut.wr_full.value) == 0
    assert int(dut.rd_empty.value) == 1

    expected = [0x11, 0x22, 0x5A, 0xE7]
    for value in expected:
        await FallingEdge(dut.wr_clk)
        dut.wr_data.value = value
        dut.wr_en.value = 1
        await RisingEdge(dut.wr_clk)
        await Timer(1, unit="ns")
        dut.wr_en.value = 0

    assert int(dut.wr_full.value) == 1

    await FallingEdge(dut.wr_clk)
    dut.wr_data.value = 0xFF
    dut.wr_en.value = 1
    await RisingEdge(dut.wr_clk)
    await Timer(1, unit="ns")
    dut.wr_en.value = 0
    assert int(dut.wr_full.value) == 1

    for _ in range(3):
        await RisingEdge(dut.rd_clk)
    assert int(dut.rd_empty.value) == 0

    observed = []
    for _ in expected:
        await FallingEdge(dut.rd_clk)
        assert int(dut.rd_empty.value) == 0
        observed.append(int(dut.rd_data.value))
        dut.rd_en.value = 1
        await RisingEdge(dut.rd_clk)
        await Timer(1, unit="ns")
        dut.rd_en.value = 0

    assert observed == expected, f"expected {expected}, got {observed}"
    assert int(dut.rd_empty.value) == 1

    await FallingEdge(dut.rd_clk)
    dut.rd_en.value = 1
    await RisingEdge(dut.rd_clk)
    await Timer(1, unit="ns")
    dut.rd_en.value = 0
    assert int(dut.rd_empty.value) == 1
