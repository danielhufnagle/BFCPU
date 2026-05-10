import cocotb
from cocotb.triggers import RisingEdge, ReadOnly

from spi_sequence_item import SPISequenceItem


class SPIOutputChecker:
    def __init__(self, dut, spi_slave):
        self.dut = dut
        self.spi_slave = spi_slave

    async def notify(self, transaction):
        if not transaction["in_valid"]:
            return

        address = transaction["address"] & SPISequenceItem.ADDR_MASK
        expected_data = transaction["data"] & SPISequenceItem.DATA_MASK

        if transaction["is_read"]:
            self.spi_slave.write_memory(address, expected_data)

        cocotb.start_soon(self._check_transaction(transaction, address, expected_data))

    async def _check_transaction(self, transaction, address, expected_data):
        if transaction["is_write"]:
            await self._wait_for_high(self.dut.done_o)
            actual_data = self.spi_slave.read_memory(address)
            assert actual_data == expected_data, (
                f"SPI write mismatch at address 0x{address:04x}: "
                f"slave memory has 0x{actual_data:02x}, expected 0x{expected_data:02x}"
            )

        elif transaction["is_read"]:
            await self._wait_for_high(self.dut.out_valid_o)
            actual_data = int(self.dut.data_o.value)
            slave_data = self.spi_slave.read_memory(address)
            assert actual_data == expected_data, (
                f"SPI read mismatch at address 0x{address:04x}: "
                f"DUT data_o is 0x{actual_data:02x}, expected 0x{expected_data:02x}"
            )
            assert slave_data == expected_data, (
                f"SPI read setup mismatch at address 0x{address:04x}: "
                f"slave memory has 0x{slave_data:02x}, expected 0x{expected_data:02x}"
            )

    async def _wait_for_high(self, signal):
        while True:
            await RisingEdge(self.dut.clk)
            await ReadOnly()
            if int(signal.value) == 1:
                return
