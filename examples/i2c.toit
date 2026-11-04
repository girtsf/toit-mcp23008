// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import i2c
import mcp23008

/**
Mirrors a button on GP1 (to GND) to an LED on GP0, for ten seconds.
*/
main:
  bus := i2c.Bus
      --sda=21
      --scl=22
  device := bus.device mcp23008.I2C-ADDRESS
  expander := mcp23008.Driver device --reset

  led := expander.pin 0 --output
  button := expander.pin 1 --input --pull-up

  deadline := Time.monotonic-us + 10_000_000
  while Time.monotonic-us < deadline:
    led.set 1 - button.get  // The button pulls the pin low when pressed.
    sleep --ms=20

  led.set 0
  print "inputs: 0b$(%08b expander.read)"

  device.close
  bus.close
