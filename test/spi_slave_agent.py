# spi_slave_agent.py

import os

import cocotb.clock
from cocotb.types import Logic, LogicArray
from cocotb.triggers import FallingEdge, First, ReadOnly, RisingEdge, Timer
from cocotb.utils import get_sim_time

if not hasattr(cocotb.clock, "BaseClock"):
    class BaseClock:
        def __init__(self, signal):
            pass

    cocotb.clock.BaseClock = BaseClock

if not hasattr(Logic, "integer"):
    Logic.integer = property(lambda self: int(self))

if not hasattr(LogicArray, "integer"):
    LogicArray.integer = property(lambda self: int(self))

from cocotbext.spi import SpiBus, SpiConfig, SpiFrameError, SpiSlaveBase


DEFAULT_SPI_RAM_SYS_HZ = 125_000_000
CS_RECOVERY_SYS_CYCLES = 50


def _get_env_int(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


class SpiRamEmuTiming:
    def __init__(self, spi_ram_sys_hz=None):
        self.spi_ram_sys_hz = (
            int(spi_ram_sys_hz)
            if spi_ram_sys_hz is not None
            else _get_env_int("SPI_RAM_SYS_HZ", DEFAULT_SPI_RAM_SYS_HZ)
        )

    @property
    def cs_recovery_ns(self):
        return 1e9 * CS_RECOVERY_SYS_CYCLES / self.spi_ram_sys_hz

    def min_sclk_period_ns(self, command, address):
        if command == SpiSlave.WRITE_CMD:
            return 1e9 * 6 / self.spi_ram_sys_hz
        if command == SpiSlave.FAST_READ_CMD:
            return 1e9 * 8 / self.spi_ram_sys_hz
        if command == SpiSlave.READ_CMD:
            divisor = 8 if address % 4 == 0 else 10
            return 1e9 * divisor / self.spi_ram_sys_hz
        return None

    def command_name(self, command, address):
        if command == SpiSlave.WRITE_CMD:
            return "WRITE"
        if command == SpiSlave.FAST_READ_CMD:
            return "FAST READ"
        if command == SpiSlave.READ_CMD:
            return "READ aligned" if address % 4 == 0 else "READ"
        return f"unknown command 0x{command:02x}"


class SpiSlave(SpiSlaveBase):
    READ_CMD = 0x03
    WRITE_CMD = 0x02
    FAST_READ_CMD = 0x0B
    MEMORY_SIZE = 1 << 16

    def __init__(self, bus, config=None, timing=None):
        self._config = config or SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
        )

        self.rx_words = []
        self.memory = {}
        self.timing = timing or SpiRamEmuTiming()
        self._last_cs_high_ns = None
        self._rise_times_ns = []
        self._active_min_sclk_period_ns = None
        self._active_timing_label = None

        super().__init__(bus)

    def read_memory(self, address):
        return self.memory.get(address % self.MEMORY_SIZE, 0)

    def write_memory(self, address, data):
        self.memory[address % self.MEMORY_SIZE] = data & 0xFF

    async def _cs_active(self):
        await ReadOnly()
        cs_value = int(self._cs.value)
        return cs_value == 0 if self._config.cs_active_low else cs_value == 1

    async def _shift(self, num_bits, tx_word=None):
        rx_word = 0
        frame_end = RisingEdge(self._cs) if self._config.cs_active_low else FallingEdge(self._cs)

        for k in range(num_bits):
            if (await First(self._sclk.value_change, frame_end)) == frame_end or self._cs.value == 1:
                raise SpiFrameError("End of frame in the middle of a transaction")
            self._record_sclk_rise()

            if self._config.cpha:
                if tx_word is not None:
                    self._miso.value = bool(tx_word & (1 << (num_bits - 1 - k)))
                else:
                    self._miso.value = self._config.data_output_idle
            else:
                rx_word |= int(self._mosi.value.integer) << (num_bits - 1 - k)

            if (await First(self._sclk.value_change, frame_end)) == frame_end or self._cs.value == 1:
                raise SpiFrameError("End of frame in the middle of a transaction")

            if self._config.cpha:
                rx_word |= int(self._mosi.value.integer) << (num_bits - 1 - k)
            else:
                if tx_word is not None:
                    self._miso.value = bool(tx_word & (1 << (num_bits - 1 - k)))
                else:
                    self._miso.value = self._config.data_output_idle

        return rx_word

    def _record_sclk_rise(self):
        if int(self._sclk.value) != 1:
            return

        now_ns = float(get_sim_time("ns"))
        if self._rise_times_ns and self._active_min_sclk_period_ns is not None:
            self._check_sclk_period(now_ns - self._rise_times_ns[-1])
        self._rise_times_ns.append(now_ns)

    def _set_operation_timing(self, command, address):
        min_period_ns = self.timing.min_sclk_period_ns(command, address)
        if min_period_ns is None:
            return

        self._active_min_sclk_period_ns = min_period_ns
        self._active_timing_label = self.timing.command_name(command, address)

        for previous_ns, current_ns in zip(self._rise_times_ns, self._rise_times_ns[1:]):
            self._check_sclk_period(current_ns - previous_ns)

    def _check_sclk_period(self, measured_period_ns):
        min_period_ns = self._active_min_sclk_period_ns
        if measured_period_ns + 1e-6 >= min_period_ns:
            return

        measured_hz = 1e9 / measured_period_ns if measured_period_ns > 0 else float("inf")
        max_hz = 1e9 / min_period_ns
        raise AssertionError(
            f"SPI RAM timing violation during {self._active_timing_label}: "
            f"measured SCLK period {measured_period_ns:.3f} ns "
            f"({measured_hz / 1e6:.3f} MHz), requires at least "
            f"{min_period_ns:.3f} ns ({max_hz / 1e6:.3f} MHz max) "
            f"for SPI_RAM_SYS_HZ={self.timing.spi_ram_sys_hz}"
        )

    async def _run(self):
        if self._config.cs_active_low:
            frame_start = FallingEdge(self._cs)
            frame_end = RisingEdge(self._cs)
        else:
            frame_start = RisingEdge(self._cs)
            frame_end = FallingEdge(self._cs)

        while True:
            self.idle.set()
            await frame_start

            now_ns = float(get_sim_time("ns"))
            if self._last_cs_high_ns is not None:
                cs_high_ns = now_ns - self._last_cs_high_ns
                if cs_high_ns + 1e-6 < self.timing.cs_recovery_ns:
                    raise AssertionError(
                        f"SPI RAM CS recovery violation: CS was high for "
                        f"{cs_high_ns:.3f} ns, requires at least "
                        f"{self.timing.cs_recovery_ns:.3f} ns "
                        f"for SPI_RAM_SYS_HZ={self.timing.spi_ram_sys_hz}"
                    )

            await self._transaction(frame_end)

    def stop(self):
        if self._run_coroutine_obj is not None:
            self._run_coroutine_obj.cancel()
            self._run_coroutine_obj = None

    async def _transaction(self, frame_end):
        self.idle.clear()
        self._rise_times_ns = []
        self._active_min_sclk_period_ns = None
        self._active_timing_label = None

        try:
            command = int(await self._shift(8))
            address = int(await self._shift(16))
            self.rx_words.append(command)
            self.rx_words.append((address >> 8) & 0xFF)
            self.rx_words.append(address & 0xFF)
            self._set_operation_timing(command, address)

            if command == self.WRITE_CMD:
                await self._write_stream(address)
            elif command == self.READ_CMD:
                await self._read_stream(address)
            elif command == self.FAST_READ_CMD:
                await self._shift(8)
                await self._read_stream(address)
            else:
                await frame_end
        except SpiFrameError:
            pass
        finally:
            self._last_cs_high_ns = float(get_sim_time("ns"))
            self.idle.set()

    async def _write_stream(self, address):
        while await self._cs_active():
            try:
                data = int(await self._shift(8))
            except SpiFrameError:
                break

            self.write_memory(address, data)
            self.rx_words.append(data)
            address = (address + 1) % self.MEMORY_SIZE

    async def _read_stream(self, address):
        while await self._cs_active():
            try:
                data = self.read_memory(address)
                await self._shift(8, tx_word=data)
            except SpiFrameError:
                break

            address = (address + 1) % self.MEMORY_SIZE


class SpiSlaveAgent:
    def __init__(self, dut, name="spi_slave", spi_ram_sys_hz=None):
        self.name = name

        self.bus = SpiBus.from_entity(
            dut.spi_bundle,
            sclk_name="sclk",
            mosi_name="mosi",
            miso_name="miso",
            cs_name="cs",
        )

        self.slave = SpiSlave(self.bus, timing=SpiRamEmuTiming(spi_ram_sys_hz))

    def queue_response(self, word):
        self.slave.write_memory(0, word)

    def load_memory(self, start_address, data):
        for offset, byte in enumerate(data):
            self.write_memory(start_address + offset, byte)

    def read_memory(self, address):
        return self.slave.read_memory(address)

    def write_memory(self, address, data):
        self.slave.write_memory(address, data)

    def get_received_words(self):
        return self.slave.rx_words

    def stop(self):
        self.slave.stop()
