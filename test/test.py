import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from spi_test_base import GenericTestBase as SPITestBase


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.in_valid_i.value = 0
    dut.command_i.value = 0
    dut.data_i.value = 0
    dut.address_i.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_spi_write_and_read(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    clock.start()

    tb = SPITestBase(dut)
    await reset_dut(dut)

    write_address = 0x1234
    write_data = 0xA5
    await tb.sequence.send_manual_write(data_i=write_data, address_i=write_address)
    await RisingEdge(dut.done_o)
    assert tb.spi_slave.read_memory(write_address) == write_data

    read_address = 0x4321
    read_data = 0x3C
    await tb.sequence.send_manual_read(data_i=read_data, address_i=read_address)
    await RisingEdge(dut.out_valid_o)
    assert int(dut.data_o.value) == read_data
