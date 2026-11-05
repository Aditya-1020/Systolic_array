import cocotb
from helper.generic import pulse_clock

MASK64 = (1 << 64) - 1


@cocotb.test()
async def test_sram_wrap_sync_read_and_byte_mask(dut):
    depth = 1 << len(dut.i_addr)
    last = depth - 1
    dut.i_clk.value = 0
    dut.i_ce.value = 0
    dut.i_we.value = 0
    dut.i_addr.value = 0
    dut.i_wdata.value = 0
    dut.i_wmask.value = 0

    async def write(addr, data, mask=MASK64):
        dut.i_ce.value = 1
        dut.i_we.value = 1
        dut.i_addr.value = addr
        dut.i_wdata.value = data & MASK64
        dut.i_wmask.value = mask & MASK64
        await pulse_clock(dut.i_clk)
        dut.i_ce.value = 0
        dut.i_we.value = 0

    async def read(addr):
        dut.i_ce.value = 1
        dut.i_we.value = 0
        dut.i_addr.value = addr
        await pulse_clock(dut.i_clk)
        value = int(dut.o_rdata.value)
        dut.i_ce.value = 0
        return value

    for address, word in ((0, 0x0123456789ABCDEF),
                          (depth // 2, 0xFEDCBA9876543210),
                          (last, 0xA55AA55A5AA55AA5)):
        await write(address, word)
        assert await read(address) == word

    # Update only low 32 bits; upper 32 bits are retained.
    await write(0, 0x00000000A5A5A5A5, 0x00000000FFFFFFFF)
    assert await read(0) == 0x01234567A5A5A5A5

    # CE low must suppress writes.
    dut.i_ce.value = 0
    dut.i_we.value = 1
    dut.i_addr.value = 0
    dut.i_wdata.value = 0
    dut.i_wmask.value = MASK64
    await pulse_clock(dut.i_clk)
    assert await read(0) == 0x01234567A5A5A5A5
