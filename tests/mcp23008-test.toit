// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import expect show *
import mcp23008
import serial.device as serial
import serial.registers as serial

IODIR ::= 0x00
IPOL ::= 0x01
GPINTEN ::= 0x02
DEFVAL ::= 0x03
INTCON ::= 0x04
IOCON ::= 0x05
GPPU ::= 0x06
INTF ::= 0x07
INTCAP ::= 0x08
GPIO ::= 0x09
OLAT ::= 0x0A

/**
A fake MCP23008 that keeps a register file and records all writes.

The $GPIO register reads back as $inputs for input pins and as $OLAT for
  output pins.
*/
class FakeDevice extends serial.Registers implements serial.Device:
  regs/ByteArray := ByteArray 11
  writes/List := []
  inputs/int := 0

  constructor:
    regs[IODIR] = 0xFF

  registers -> serial.Registers:
    return this

  read amount/int -> ByteArray:
    unreachable

  write bytes/ByteArray -> none:
    unreachable

  read-bytes register/int count/int -> ByteArray:
    expect-equals 1 count
    if register == GPIO:
      iodir := regs[IODIR]
      return #[(inputs & iodir) | (regs[OLAT] & ~iodir & 0xFF)]
    return #[regs[register]]

  write-bytes register/int data/ByteArray -> none:
    expect-equals 1 data.size
    regs[register] = data[0]
    writes.add [register, data[0]]

  take -> List:
    result := writes
    writes = []
    return result

main:
  test-constructor
  test-pin-output
  test-pin-input
  test-pin-lifecycle
  test-bulk
  test-interrupts
  test-invalid

test-constructor:
  device := FakeDevice
  device.regs[IODIR] = 0x0F
  device.regs[OLAT] = 0x30
  device.regs[GPPU] = 0x01
  expander := mcp23008.Driver device
  expect-equals [] device.take

  // The shadows are read from the chip: already-set bits aren't rewritten.
  expander.pin 4 --output --value=1
  expect-equals [] device.take
  expander.pin 0 --output
  expect-equals [[GPPU, 0x00], [IODIR, 0x0E]] device.take

  device.regs[GPINTEN] = 0x55
  device.regs[IOCON] = 0x04
  mcp23008.Driver device --reset
  expect-equals [
    [IODIR, 0xFF],
    [IPOL, 0],
    [GPINTEN, 0],
    [DEFVAL, 0],
    [INTCON, 0],
    [IOCON, 0],
    [GPPU, 0],
    [OLAT, 0],
  ] device.take

test-pin-output:
  device := FakeDevice
  expander := mcp23008.Driver device

  // The latch is set before the direction, so the pin never glitches.
  pin := expander.pin 3 --output --value=1
  expect-equals [[OLAT, 0x08], [IODIR, 0xF7]] device.take
  expect-equals 1 pin.get

  pin.set 0
  expect-equals [[OLAT, 0x00]] device.take
  expect-equals 0 pin.get
  pin.set 0
  expect-equals [] device.take

  other := expander.pin 5 --output
  expect-equals [[IODIR, 0xD7]] device.take
  other.set 1
  pin.set 1
  expect-equals [[OLAT, 0x20], [OLAT, 0x28]] device.take

  // Back to input.
  pin.configure --input
  expect-equals [[IODIR, 0xDF]] device.take

test-pin-input:
  device := FakeDevice
  expander := mcp23008.Driver device

  pin := expander.pin 2 --input --pull-up
  expect-equals [[GPPU, 0x04]] device.take
  device.inputs = 0x04
  expect-equals 1 pin.get
  device.inputs = 0xFB
  expect-equals 0 pin.get

  pin.set-pull --off
  expect-equals [[GPPU, 0x00]] device.take
  pin.set-pull --up
  expect-equals [[GPPU, 0x04]] device.take
  pin.configure --input
  expect-equals [[GPPU, 0x00]] device.take

  // Without flags the pin keeps its configuration.
  plain := expander.pin 7
  expect-equals [] device.take
  expect-equals 7 plain.num

  device.inputs = 0x00
  task::
    sleep --ms=30
    device.inputs = 0x04
  pin.wait-for 1
  expect-equals 1 pin.get

  expect-throw "UNSUPPORTED": pin.configure --input --pull-down
  expect-throw "UNSUPPORTED": pin.configure --output --open-drain
  expect-throw "UNSUPPORTED": pin.set-pull --down
  expect-throw "UNSUPPORTED": pin.set-open-drain true
  pin.set-open-drain false
  expect-throw "INVALID_ARGUMENT": pin.set-pull
  expect-equals [] device.take

test-pin-lifecycle:
  device := FakeDevice
  expander := mcp23008.Driver device

  pin := expander.pin 0
  expect-throw "ALREADY_IN_USE": expander.pin 0
  pin.close
  pin.close
  expect-throw "ALREADY_CLOSED": pin.get
  expect-throw "ALREADY_CLOSED": pin.set 1
  expander.pin 0

test-bulk:
  device := FakeDevice
  expander := mcp23008.Driver device

  expander.write 0xA5
  expect-equals [[OLAT, 0xA5]] device.take
  device.inputs = 0x3C
  expect-equals 0x3C expander.read

  // Pins see the latch written in bulk.
  expander.pin 0 --output --value=1
  expect-equals [[IODIR, 0xFE]] device.take
  expect-equals 0x3D expander.read

test-interrupts:
  device := FakeDevice
  expander := mcp23008.Driver device

  expander.configure-interrupts --on-change=0x0F --on-compare=0x30 --default-value=0x10
  expect-equals [
    [GPINTEN, 0x00],
    [DEFVAL, 0x10],
    [INTCON, 0x30],
    [GPINTEN, 0x3F],
  ] device.take

  device.regs[IOCON] = 0x20  // SEQOP must be preserved.
  expander.configure-interrupt-pin --open-drain
  expander.configure-interrupt-pin --active-high
  expander.configure-interrupt-pin
  expect-equals [[IOCON, 0x24], [IOCON, 0x22], [IOCON, 0x20]] device.take

  device.regs[INTF] = 0x02
  device.regs[INTCAP] = 0x42
  expect-equals 0x02 expander.interrupt-flags
  expect-equals 0x42 expander.interrupt-capture

test-invalid:
  device := FakeDevice
  expander := mcp23008.Driver device
  expect-throw "INVALID_ARGUMENT": expander.pin -1
  expect-throw "INVALID_ARGUMENT": expander.pin 8
  expect-throw "OUT_OF_RANGE": expander.write 0x100
  expect-throw "OUT_OF_RANGE": expander.write -1
  expect-throw "OUT_OF_RANGE": expander.configure-interrupts --on-change=0x100
  expect-throw "INVALID_ARGUMENT":
    expander.configure-interrupts --on-change=0x01 --on-compare=0x03
  expect-equals [] device.take
