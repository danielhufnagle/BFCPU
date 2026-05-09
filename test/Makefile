# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info
# defaults
SIM ?= verilator
TOPLEVEL_LANG ?= systemverilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.sv

ifneq ($(GATES),yes)
# RTL simulation:
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

# Simulator-specific flags for SystemVerilog
ifeq ($(SIM),verilator)
	# Verilator: enable FST waveforms and relax some lint checks
	EXTRA_ARGS += --trace-fst --trace-structs
	EXTRA_ARGS += -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING
	endif
	ifeq ($(SIM),icarus)
	# Icarus: enable SystemVerilog 2012 mode
COMPILE_ARGS += -g2012
endif

else
	# Gate level simulation: force Icarus (Verilator doesn't play nicely with PDK cells)
	SIM = icarus
	SIM_BUILD = sim_build/gl
	COMPILE_ARGS    += -DGL_TEST
	COMPILE_ARGS    += -DFUNCTIONAL
	COMPILE_ARGS    += -DSIM
	VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v
	VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v
	# this gets copied in by the GDS action workflow
	VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS += -I$(SRC_DIR)
# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
VERILOG_SOURCES += $(PWD)/tb.sv

TOPLEVEL = tb
# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test
# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
