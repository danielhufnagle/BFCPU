from dataclasses import dataclass, field
from typing import Any, Dict, Self

from cocotb.types import Logic, LogicArray

from tb_utils.abstract_transactions import AbstractTransaction

@dataclass
class SPISequenceItem(AbstractTransaction):
    DATA_W = 8
    ADDR_W = 16
    DATA_MASK = (1 << DATA_W) - 1
    ADDR_MASK = (1 << ADDR_W) - 1
    WRITE_COMMAND = 0
    READ_COMMAND = 1

    # Transaction input ports on spi_internal.sv. The generic driver drives
    # these by name; SPI interface pins are handled by the SPI slave model.
    in_valid_i: Logic = field(default_factory=lambda: Logic("0"))
    command_i: Logic = field(default_factory=lambda: Logic("0"))  # WRITE_T = 0, READ_T = 1
    data_i: LogicArray = field(default_factory=lambda: LogicArray("0" * SPISequenceItem.DATA_W))
    address_i: LogicArray = field(
        default_factory=lambda: LogicArray("0" * SPISequenceItem.ADDR_W)
    )

    def __post_init__(self):
        self.data_i = self._logic_array(self.data_i, self.DATA_W, self.DATA_MASK)
        self.address_i = self._logic_array(self.address_i, self.ADDR_W, self.ADDR_MASK)

    @staticmethod
    def _to_int(value: Any, default: int = 0) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _logic_array(value: Any, width: int, mask: int) -> LogicArray:
        try:
            raw_value = int(value) & mask
            return LogicArray.from_unsigned(raw_value, width)
        except (TypeError, ValueError):
            return LogicArray("0" * width)

    @classmethod
    def invalid_seq_item(cls) -> Self:
        return cls(
            in_valid_i=Logic(0),
            command_i=Logic(0),
            data_i=LogicArray.from_unsigned(0, cls.DATA_W),
            address_i=LogicArray.from_unsigned(0, cls.ADDR_W),
        )

    @property
    def valid(self) -> bool:
        return bool(self._to_int(self.in_valid_i, 0))

    @valid.setter
    def valid(self, value: bool):
        self.in_valid_i = Logic(value)

    @property
    def is_write(self) -> bool:
        return self._to_int(self.command_i, self.WRITE_COMMAND) == self.WRITE_COMMAND

    @property
    def is_read(self) -> bool:
        return self._to_int(self.command_i, self.WRITE_COMMAND) == self.READ_COMMAND

    @property
    def to_data(self) -> Dict[str, Any]:
        return {
            "in_valid": self.valid,
            "command": self._to_int(self.command_i, 0),
            "is_write": self.is_write,
            "is_read": self.is_read,
            "data": self._to_int(self.data_i, 0),
            "address": self._to_int(self.address_i, 0),
        }
