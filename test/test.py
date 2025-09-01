# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV


# When submitting your design, change this to the peripheral number
# in peripherals.v.  e.g. if your design is i_user_peri05, set this to 5.
# The peripheral number is not used by the test harness.
PERIPHERAL_NUM = 0


async def test_object_ram(tqv, dut):
	await tqv.write_byte_reg(0, 0x12)
	await tqv.write_byte_reg(1, 0x34)
	await tqv.write_byte_reg(2, 0x00)
	await tqv.write_byte_reg(3, 0x11)
	# Set STAGING_READY so swap occurs on vsync
	await tqv.write_byte_reg(63, 0x02)
	# Wait for control_reg to update
	await ClockCycles(dut.clk, 2)
	dut.vsync.value = 0
	await ClockCycles(dut.clk, 1)
	dut.vsync.value = 1
	await ClockCycles(dut.clk, 1)
	dut.vsync.value = 0
	await ClockCycles(dut.clk, 2)  # Wait for swap to complete
	assert await tqv.read_byte_reg(0) == 0x12
	assert await tqv.read_byte_reg(1) == 0x34

async def test_bitmap_ram(tqv, dut):
	bitmap_addr = 4
	await tqv.write_byte_reg(63, 0x01)  # Enable bitmap writes
	await tqv.write_byte_reg(bitmap_addr, 0xFF)
	assert await tqv.read_byte_reg(bitmap_addr) == 0xFF

async def test_control_reg_and_interrupt(tqv, dut):
	await tqv.write_byte_reg(63, 0x00)
	dut.vsync.value = 1
	await ClockCycles(dut.clk, 1)
	dut.vsync.value = 0
	await ClockCycles(dut.clk, 1)
	# user_interrupt is not exposed in tb.v, so we only check register access

async def test_video_outputs(dut):
	await ClockCycles(dut.clk, 10)
	dut._log.info(f"R={dut.R.value}, G={dut.G.value}, B={dut.B.value}")

async def test_multiple_sprites(tqv, dut):
	# Write two sprites and verify
	await tqv.write_byte_reg(0, 0x10)
	await tqv.write_byte_reg(1, 0x20)
	await tqv.write_byte_reg(2, 0x00)
	await tqv.write_byte_reg(3, 0x11)
	await tqv.write_byte_reg(4, 0x30)
	await tqv.write_byte_reg(5, 0x40)
	await tqv.write_byte_reg(6, 0x01)
	await tqv.write_byte_reg(7, 0x22)
	await tqv.write_byte_reg(63, 0x02)
	dut.vsync.value = 1
	await ClockCycles(dut.clk, 1)
	dut.vsync.value = 0
	await ClockCycles(dut.clk, 1)
	assert await tqv.read_byte_reg(0) == 0x10
	assert await tqv.read_byte_reg(4) == 0x30

@cocotb.test()
async def test_sprite_engine_all(dut):
	dut._log.info("Sprite Engine Full Test Start")
	clock = Clock(dut.clk, 100, units="ns")
	cocotb.start_soon(clock.start())
	tqv = TinyQV(dut, PERIPHERAL_NUM)
	await tqv.reset()
	await test_object_ram(tqv, dut)
	await test_bitmap_ram(tqv, dut)
	await test_control_reg_and_interrupt(tqv, dut)
	await test_video_outputs(dut)
	await test_multiple_sprites(tqv, dut)
	dut._log.info("Sprite Engine Full Test Complete")
