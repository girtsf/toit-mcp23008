// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import .driver

export *

/**
Driver for the MCP23008 8-bit I2C GPIO expander.

The MCP23008 has eight GPIO pins, each configurable as a push-pull output
  or as an input with an optional 100k pull-up. It answers on addresses
  $I2C-ADDRESS to $I2C-ADDRESS-MAX, selected with the A0-A2 pins.

Use $Driver.pin to get a $Pin, which implements the SDK's `gpio.Pin`
  interface. $Driver.read and $Driver.write access all pins at once, and
  $Driver.configure-interrupts sets up the INT output.

# Examples
```
import i2c
import mcp23008

main:
  bus := i2c.Bus --sda=21 --scl=22
  device := bus.device mcp23008.I2C-ADDRESS
  expander := mcp23008.Driver device
  led := expander.pin 0 --output
  button := expander.pin 1 --input --pull-up
  led.set 1 - button.get
  device.close
  bus.close
```
*/
