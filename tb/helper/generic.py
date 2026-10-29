
from cocotb.triggers import RisingEdge, FallingEdge, Timer


async def pulse_clock(clk, pulse_ns=1, low_ns=1):
    """Generate one isolated positive clock pulse."""
    clk.value = 0
    await Timer(low_ns, unit="ns")
    clk.value = 1
    await Timer(pulse_ns, unit="ns")
    clk.value = 0
    await Timer(low_ns, unit="ns")


async def wait_clock_cycles(dut, cycles=1, clk_name="clk"):
    """Wait for a specified number of rising edges."""
    clk = getattr(dut, clk_name)
    for _ in range(cycles):
        await RisingEdge(clk)
        await Timer(1, unit="ns")


async def wait_for(
    dut, signal, expected, label, limit=100, clk_name="clk"
):
    """Wait for a signal to reach an expected unsigned integer value."""
    for _ in range(limit):
        await Timer(1, unit="ns")
        if int(signal.value) == expected:
            return

        await wait_clock_cycles(dut, 1, clk_name)

    raise AssertionError(
        f"Timeout waiting for {label}={expected}; "
        f"got {signal.value}"
    )


def wrap_signed(value: int, width: int) -> int:
    """Wrap an integer to a signed two's-complement width."""
    mask = (1 << width) - 1
    value &= mask

    if value & (1 << (width - 1)):
        value -= 1 << width

    return value


def read_signed(signal) -> int:
    """Read a Cocotb logic signal as a signed integer."""
    return int(signal.value.to_signed())


def write_signed(signal, value: int, width: int):
    """Drive a signed integer after checking its representable range."""
    minimum = -(1 << (width - 1))
    maximum = (1 << (width - 1)) - 1

    if not minimum <= value <= maximum:
        raise ValueError(
            f"{value} does not fit in signed {width}-bit range "
            f"[{minimum}, {maximum}]"
        )

    signal.value = value


async def pulse_signal_one_cycle(dut, signal, clk_name="clk"):
    """Assert a control signal for one cycle of a running clock."""
    clk = getattr(dut, clk_name)

    await FallingEdge(clk)
    signal.value = 1
    await RisingEdge(clk)
    await FallingEdge(clk)
    signal.value = 0
