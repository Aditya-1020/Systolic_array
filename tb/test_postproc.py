import cocotb
from helper.generic import pulse_clock, pack_lanes, unpack_lanes

N = 8
DW = 8
ACC_W = 19


@cocotb.test()
async def test_postproc_two_gated_stages(dut):
    dut.i_clk.value = 0
    dut.i_rstn.value = 0
    dut.i_post_proc_en.value = 0
    dut.i_round_const.value = 0
    dut.i_relu_en.value = 0
    dut.i_shift.value = 0
    dut.i_arr_valid.value = 0
    dut.i_sys_data.value = 0

    await pulse_clock(dut.i_clk)
    await pulse_clock(dut.i_clk)
    dut.i_rstn.value = 1
    await pulse_clock(dut.i_clk)

    data = [-1000, -129, -128, -1, 0, 1, 127, 1000]
    dut.i_post_proc_en.value = 1
    dut.i_round_const.value = 0
    dut.i_relu_en.value = 1
    dut.i_shift.value = 0
    dut.i_sys_data.value = pack_lanes(data, ACC_W)
    dut.i_arr_valid.value = 1

    # Stage 1 captures on the first enabled root-clock edge.
    await pulse_clock(dut.i_clk)
    assert int(dut.o_round_valid.value) == 1
    assert unpack_lanes(dut.o_round_data, N, ACC_W) == data

    # Stage 2 captures the registered stage-1 value on the following edge.
    dut.i_arr_valid.value = 0
    await pulse_clock(dut.i_clk)
    assert int(dut.o_relu_valid.value) == 1
    expected = [0, 0, 0, 0, 0, 1, 127, 127]
    assert unpack_lanes(dut.o_post_proc_data, N, DW) == expected

    # With no new valid input, the pipeline drains and the data flops hold.
    await pulse_clock(dut.i_clk)
    assert int(dut.o_round_valid.value) == 0
    assert int(dut.o_relu_valid.value) == 0
    assert unpack_lanes(dut.o_post_proc_data, N, DW) == expected
