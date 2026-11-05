from cocotb.triggers import Timer

async def pulse_clock(clk, high_ns=5, low_ns=5):
    clk.value = 0
    await Timer(low_ns, unit="ns")
    clk.value = 1
    await Timer(high_ns, unit="ns")
    clk.value = 0
    await Timer(low_ns, unit="ns")


def wrap_signed(value: int, width: int) -> int:
    mask = (1 << width) - 1
    value &= mask
    return value - (1 << width) if value & (1 << (width - 1)) else value


def pack_lanes(values, width: int) -> int:
    mask = (1 << width) - 1
    packed = 0
    for lane, value in enumerate(values):
        packed |= (int(value) & mask) << (lane * width)
    return packed


def unpack_lanes(value, count: int, width: int, signed=True):
    raw = int(value.value) if hasattr(value, "value") else int(value)
    mask = (1 << width) - 1
    lanes = [(raw >> (lane * width)) & mask for lane in range(count)]
    return [wrap_signed(v, width) for v in lanes] if signed else lanes


def read_signed(signal) -> int:
    return int(signal.value.to_signed())


def write_signed(signal, value: int, width: int):
    lo = -(1 << (width - 1))
    hi = (1 << (width - 1)) - 1
    if not lo <= value <= hi:
        raise ValueError(f"{value} does not fit signed {width}-bit range")
    signal.value = value & ((1 << width) - 1)
