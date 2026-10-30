from cocotb.triggers import FallingEdge, RisingEdge, Timer

async def pulse_clock(clk, pulse_ns=1, low_ns=1):
    clk.value = 0
    await Timer(low_ns, unit="ns")
    clk.value = 1
    await Timer(pulse_ns, unit="ns")
    clk.value = 0
    await Timer(low_ns, unit="ns")

async def wait_clock_cycles(dut, cycles=1, clk_name="clk"):
    clk = getattr(dut, clk_name)
    for _ in range(cycles):
        await RisingEdge(clk)
        await Timer(1, unit="ns")

async def wait_for(dut, signal, expected, label, limit=100, clk_name="clk"):
    for _ in range(limit):
        await Timer(1, unit="ns")
        if int(signal.value) == expected:
            return
        await wait_clock_cycles(dut, 1, clk_name)
    raise AssertionError(f"Timeout waiting for {label}={expected}; got {signal.value}")

def wrap_signed(value: int, width: int) -> int:
    value &= (1 << width) - 1
    if value & (1 << (width - 1)):
        value -= 1 << width
    return value

def pack_signed_lanes(values, width: int) -> int:
    mask = (1 << width) - 1
    packed = 0
    for index, value in enumerate(values):
        packed |= (int(value) & mask) << (index * width)
    return packed


def unpack_signed_lanes(value, count: int, width: int) -> list[int]:
    raw = int(value.value) if hasattr(value, "value") else int(value)
    mask = (1 << width) - 1
    return [wrap_signed((raw >> (index * width)) & mask, width) for index in range(count)]

def read_signed(signal) -> int:
    return int(signal.value.to_signed())

def write_signed(signal, value: int, width: int):
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1
    if not minimum <= value <= maximum:
        raise ValueError(f"{value} does not fit signed {width}-bit range")
    signal.value = value


async def pulse_signal_one_cycle(dut, signal, clk_name="clk"):
    clk = getattr(dut, clk_name)
    await FallingEdge(clk)
    signal.value = 1
    await RisingEdge(clk)
    await FallingEdge(clk)
    signal.value = 0
