# MCP23008

Toit driver for the MCP23008 8-bit I2C GPIO expander.

## Usage

```toit
import i2c
import mcp23008

main:
  bus := i2c.Bus --sda=21 --scl=22
  device := bus.device mcp23008.I2C-ADDRESS  // 0x20..0x27, set by A0-A2.
  expander := mcp23008.Driver device --reset

  led := expander.pin 0 --output
  button := expander.pin 1 --input --pull-up
  led.set 1 - button.get

  expander.write 0xFF          // Set the output latch of all pins.
  print expander.read          // Read the levels of all pins.

  device.close
  bus.close
```

Pins returned by `Driver.pin` implement the SDK's `gpio.Pin` interface, so
they work with anything that takes a `gpio.Pin` (e.g. `gpio.InvertedPin`).
`wait-for` and `do` poll the expander every 10ms.

The driver caches the direction, pull-up and output-latch registers. They are
read once in the constructor (or reset with `--reset`); don't change them
behind the driver's back.

Interrupts are configured with `configure-interrupts` (on change, or on
difference from a default value) and `configure-interrupt-pin` (INT pin
polarity/open-drain). Read `interrupt-flags` and `interrupt-capture` to
handle them; reading the capture clears the interrupt.

Limitations:
- No pull-downs and no open-drain pin outputs (hardware); both throw
  `UNSUPPORTED`.
- Input polarity inversion (IPOL) isn't exposed; use `gpio.InvertedPin`.

See `examples/i2c.toit` for a runnable example.

## AI Disclosure

Robots wrote most of this.
