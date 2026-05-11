# spi_slave_agent.py

import cocotb.clock
from cocotb.types import Logic, LogicArray
from cocotb.triggers import ReadOnly

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


class SpiSlave(SpiSlaveBase):
    READ_CMD = 0x03
    WRITE_CMD = 0x02
    FAST_READ_CMD = 0x0B
    MEMORY_SIZE = 1 << 16

    def __init__(self, bus, config=None):
        self._config = config or SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
        )

        self.rx_words = []
        self.memory = {}

        super().__init__(bus)

    def read_memory(self, address):
        return self.memory.get(address % self.MEMORY_SIZE, 0)

    def write_memory(self, address, data):
        self.memory[address % self.MEMORY_SIZE] = data & 0xFF

    async def _cs_active(self):
        await ReadOnly()
        cs_value = int(self._cs.value)
        return cs_value == 0 if self._config.cs_active_low else cs_value == 1

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        try:
            command = int(await self._shift(8))
            address = int(await self._shift(16))
            self.rx_words.append(command)
            self.rx_words.append((address >> 8) & 0xFF)
            self.rx_words.append(address & 0xFF)

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
    def __init__(self, dut, name="spi_slave"):
        self.name = name

        self.bus = SpiBus.from_entity(
            dut.spi_bundle,
            sclk_name="sclk",
            mosi_name="mosi",
            miso_name="miso",
            cs_name="cs",
        )

        self.slave = SpiSlave(self.bus)

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
