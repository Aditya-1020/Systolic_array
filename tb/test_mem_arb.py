import cocotb
from cocotb.triggers import Timer
from helper.generic import pulse_clock

MASK64 = (1 << 64) - 1


@cocotb.test()
async def test_mem_arb_priority_and_read_routing(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    for name in ("i_core_req", "i_core_we", "i_core_addr", "i_core_wdata", "i_core_wmask",
                 "i_sw_req", "i_sw_we", "i_sw_addr", "i_sw_wdata", "i_sw_wmask"):
        getattr(dut, name).value = 0

    await pulse_clock(dut.i_clk)
    dut.i_rstn.value = 1
    await pulse_clock(dut.i_clk)

    # Software writes location 3.
    dut.i_sw_req.value = 1
    dut.i_sw_we.value = 1
    dut.i_sw_addr.value = 3
    dut.i_sw_wdata.value = 0x1122334455667788
    dut.i_sw_wmask.value = MASK64
    await Timer(1, unit="ns")
    assert int(dut.o_sw_gnt.value) == 1
    await pulse_clock(dut.i_clk)
    dut.i_sw_req.value = 0
    dut.i_sw_we.value = 0

    # A software read returns one cycle after its grant.
    dut.i_sw_req.value = 1
    dut.i_sw_we.value = 0
    dut.i_sw_addr.value = 3
    await Timer(1, unit="ns")
    assert int(dut.o_sw_gnt.value) == 1
    await pulse_clock(dut.i_clk)
    assert int(dut.o_sw_rvalid.value) == 1
    assert int(dut.o_sw_rdata.value) == 0x1122334455667788
    dut.i_sw_req.value = 0
    await pulse_clock(dut.i_clk)

    # Simultaneous requests: core wins and software is not granted.
    dut.i_core_req.value = 1
    dut.i_core_we.value = 1
    dut.i_core_addr.value = 3
    dut.i_core_wdata.value = 0xDEADBEEFCAFEBABE
    dut.i_core_wmask.value = MASK64
    dut.i_sw_req.value = 1
    dut.i_sw_we.value = 1
    dut.i_sw_addr.value = 4
    dut.i_sw_wdata.value = 0x0102030405060708
    dut.i_sw_wmask.value = MASK64
    await Timer(1, unit="ns")
    assert int(dut.o_core_gnt.value) == 1
    assert int(dut.o_sw_gnt.value) == 0
    await pulse_clock(dut.i_clk)
    dut.i_core_req.value = 0
    await Timer(1, unit="ns")

    # The previously stalled software request is now granted.
    assert int(dut.o_sw_gnt.value) == 1
    await pulse_clock(dut.i_clk)
    dut.i_sw_req.value = 0
    dut.i_sw_we.value = 0

    # Core reads location 3; software reads location 4.
    dut.i_core_req.value = 1
    dut.i_core_we.value = 0
    dut.i_core_addr.value = 3
    dut.i_sw_req.value = 1
    dut.i_sw_we.value = 0
    dut.i_sw_addr.value = 4
    await Timer(1, unit="ns")
    assert int(dut.o_core_gnt.value) == 1
    assert int(dut.o_sw_gnt.value) == 0
    await pulse_clock(dut.i_clk)
    assert int(dut.o_core_rvalid.value) == 1
    assert int(dut.o_sw_rvalid.value) == 0
    assert int(dut.o_core_rdata.value) == 0xDEADBEEFCAFEBABE

    # Release core; the waiting software read proceeds on the next cycle.
    dut.i_core_req.value = 0
    await Timer(1, unit="ns")
    assert int(dut.o_sw_gnt.value) == 1
    await pulse_clock(dut.i_clk)
    assert int(dut.o_sw_rvalid.value) == 1
    assert int(dut.o_sw_rdata.value) == 0x0102030405060708
