# spi_slave_agent.py

from cocotbext.spi import SpiBus, SpiConfig, SpiSlaveBase


class SpiSlave(SpiSlaveBase):
    def __init__(self, bus, config=None):
        self._config = config or SpiConfig(
            word_width=8,
            cpol=False,
            cpha=False,
            msb_first=True,
            cs_active_low=True,
        )

        self.rx_words = []
        self.tx_queue = []

        super().__init__(bus)

    def add_response(self, word):
        self.tx_queue.append(word)

    async def _transaction(self, frame_start, frame_end):
        await frame_start
        self.idle.clear()

        tx_word = self.tx_queue.pop(0) if self.tx_queue else 0x00
        rx_word = int(await self._shift(8, tx_word=tx_word))

        self.rx_words.append(rx_word)

        await frame_end
        self.idle.set()


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
        self.slave.add_response(word)

    def get_received_words(self):
        return self.slave.rx_words