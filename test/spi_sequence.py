import random

from cocotb.types import Logic, LogicArray

from spi_sequence_item import SPISequenceItem
from tb_utils.generic_sequence import GenericSequence


class SPISequence(GenericSequence):
    DATA_W = SPISequenceItem.DATA_W
    ADDR_W = SPISequenceItem.ADDR_W
    DATA_MASK = SPISequenceItem.DATA_MASK
    ADDR_MASK = SPISequenceItem.ADDR_MASK
    WRITE_COMMAND = SPISequenceItem.WRITE_COMMAND
    READ_COMMAND = SPISequenceItem.READ_COMMAND

    def __init__(self, driver, *subscribers):
        super().__init__(driver, *subscribers)
        self.default_item = SPISequenceItem.invalid_seq_item()

    @staticmethod
    def _to_logic(value: bool | int) -> Logic:
        return Logic("1" if value else "0")

    @staticmethod
    def _to_logic_array(value: int, width: int, mask: int) -> LogicArray:
        return LogicArray.from_unsigned(int(value) & mask, width)

    def set_in_valid_i(self, value: bool | int):
        self.default_item.in_valid_i = self._to_logic(value)

    def set_command_i(self, value: bool | int):
        self.default_item.command_i = self._to_logic(value)

    def set_data_i(self, value: int):
        self.default_item.data_i = self._to_logic_array(
            value,
            self.DATA_W,
            self.DATA_MASK,
        )

    def set_address_i(self, value: int):
        self.default_item.address_i = self._to_logic_array(
            value,
            self.ADDR_W,
            self.ADDR_MASK,
        )

    def _make_item(
        self,
        *,
        in_valid_i: bool | int | None = None,
        command_i: bool | int | None = None,
        data_i: int | None = None,
        address_i: int | None = None,
    ) -> SPISequenceItem:
        return SPISequenceItem(
            in_valid_i=(
                self.default_item.in_valid_i
                if in_valid_i is None
                else self._to_logic(in_valid_i)
            ),
            command_i=(
                self.default_item.command_i
                if command_i is None
                else self._to_logic(command_i)
            ),
            data_i=(
                self.default_item.data_i
                if data_i is None
                else self._to_logic_array(data_i, self.DATA_W, self.DATA_MASK)
            ),
            address_i=(
                self.default_item.address_i
                if address_i is None
                else self._to_logic_array(address_i, self.ADDR_W, self.ADDR_MASK)
            ),
        )

    async def send_manual_read(self, data_i: int, address_i: int):
        seq_item = self._make_item(
            in_valid_i=1,
            command_i=self.READ_COMMAND,
            data_i=data_i,
            address_i=address_i,
        )
        await self.notify_subscribers(seq_item.to_data)
        await self.add_transaction(seq_item)

    async def send_manual_write(self, data_i: int, address_i: int):
        seq_item = self._make_item(
            in_valid_i=1,
            command_i=self.WRITE_COMMAND,
            data_i=data_i,
            address_i=address_i,
        )
        await self.notify_subscribers(seq_item.to_data)
        await self.add_transaction(seq_item)

    async def send_random_read(self):
        await self.send_manual_read(
            data_i=random.getrandbits(self.DATA_W),
            address_i=random.getrandbits(self.ADDR_W),
        )

    async def send_random_write(self):
        await self.send_manual_write(
            data_i=random.getrandbits(self.DATA_W),
            address_i=random.getrandbits(self.ADDR_W),
        )

    async def send_invalid_read(self):
        seq_item = self._make_item(
            in_valid_i=0,
            command_i=self.READ_COMMAND,
            data_i=random.getrandbits(self.DATA_W),
            address_i=random.getrandbits(self.ADDR_W),
        )
        await self.notify_subscribers(seq_item.to_data)
        await self.add_transaction(seq_item)

    async def send_invalid_write(self):
        seq_item = self._make_item(
            in_valid_i=0,
            command_i=self.WRITE_COMMAND,
            data_i=random.getrandbits(self.DATA_W),
            address_i=random.getrandbits(self.ADDR_W),
        )
        await self.notify_subscribers(seq_item.to_data)
        await self.add_transaction(seq_item)
