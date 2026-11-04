// Copyright (C) 2026 Girts Folkmanis.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import gpio
import monitor
import serial.device as serial
import serial.registers as serial

/** Default I2C address of the MCP23008 (A0, A1 and A2 tied low). */
I2C-ADDRESS ::= 0x20

/** Highest I2C address of the MCP23008 (A0, A1 and A2 tied high). */
I2C-ADDRESS-MAX ::= 0x27

/** Number of GPIO pins. */
PIN-COUNT ::= 8

/**
Driver for the MCP23008 8-bit GPIO expander.

Individual pins are available through $pin, which returns a $gpio.Pin. All
  pins can be read and written at once with $read and $write.

The driver caches the direction, pull-up and output-latch registers. It
  reads them once in the constructor and assumes that nothing else changes
  them afterwards.
*/
class Driver:
  static IODIR-REGISTER_ ::= 0x00
  static IPOL-REGISTER_ ::= 0x01
  static GPINTEN-REGISTER_ ::= 0x02
  static DEFVAL-REGISTER_ ::= 0x03
  static INTCON-REGISTER_ ::= 0x04
  static IOCON-REGISTER_ ::= 0x05
  static GPPU-REGISTER_ ::= 0x06
  static INTF-REGISTER_ ::= 0x07
  static INTCAP-REGISTER_ ::= 0x08
  static GPIO-REGISTER_ ::= 0x09
  static OLAT-REGISTER_ ::= 0x0A

  static IOCON-ODR_ ::= 0x04
  static IOCON-INTPOL_ ::= 0x02

  registers_/serial.Registers
  mutex_/monitor.Mutex ::= monitor.Mutex
  pins_/List ::= List PIN-COUNT

  // Shadows of the chip's registers.
  iodir_/int := ?
  gppu_/int := ?
  olat_/int := ?

  /**
  Constructs a driver for the MCP23008 behind the given $device.

  If $reset is true, writes the power-on defaults to all configuration
    registers: all pins are inputs without pull-ups, interrupts are disabled,
    and the output latch is 0. Otherwise the current configuration is kept.

  The driver does not take ownership of the $device.
  */
  constructor device/serial.Device --reset/bool=false:
    registers_ = device.registers
    if reset:
      registers_.write-u8 IODIR-REGISTER_ 0xFF
      [
        IPOL-REGISTER_,
        GPINTEN-REGISTER_,
        DEFVAL-REGISTER_,
        INTCON-REGISTER_,
        IOCON-REGISTER_,
        GPPU-REGISTER_,
        OLAT-REGISTER_,
      ].do: registers_.write-u8 it 0
    iodir_ = registers_.read-u8 IODIR-REGISTER_
    gppu_ = registers_.read-u8 GPPU-REGISTER_
    olat_ = registers_.read-u8 OLAT-REGISTER_

  /**
  Returns the pin with the given $num (0 to $PIN-COUNT - 1).

  A pin can only be opened once. Close it with $Pin.close before opening it
    again.

  If neither $input nor $output is given, the pin keeps its current
    configuration. Otherwise it is configured as with $gpio.Pin.configure: an
    $output pin starts with the given $value, and an $input pin can have a
    $pull-up.
  */
  pin num/int -> Pin
      --input/bool=false
      --output/bool=false
      --pull-up/bool=false
      --value/int=0:
    check-pin_ num
    if pins_[num]: throw "ALREADY_IN_USE"
    result := Pin.from-driver_ this num
    if input or output:
      result.configure
          --input=input
          --output=output
          --pull-up=pull-up
          --value=(output ? value : null)
    pins_[num] = result
    return result

  /**
  Reads the levels of all pins.

  Bit n of the result is the level of pin n. Output pins report the level
    they are driving.
  */
  read -> int:
    return registers_.read-u8 GPIO-REGISTER_

  /**
  Sets the output latch of all pins to $value.

  Bit n of $value is the level of pin n. Only pins configured as outputs
    drive their level.
  */
  write value/int -> none:
    check-byte_ value
    mutex_.do:
      registers_.write-u8 OLAT-REGISTER_ value
      olat_ = value

  /**
  Configures which pins trigger an interrupt.

  Pins in the $on-change mask trigger when their level changes. Pins in the
    $on-compare mask trigger while their level differs from the
    corresponding bit in $default-value. The two masks must not overlap.

  Interrupts are signaled on the INT pin (see $configure-interrupt-pin)
    and are cleared by reading $interrupt-capture or $read.
  */
  configure-interrupts --on-change/int=0 --on-compare/int=0 --default-value/int=0 -> none:
    check-byte_ on-change
    check-byte_ on-compare
    check-byte_ default-value
    if on-change & on-compare != 0: throw "INVALID_ARGUMENT"
    mutex_.do:
      // Disable first, so that the new mode doesn't trigger spuriously.
      registers_.write-u8 GPINTEN-REGISTER_ 0
      registers_.write-u8 DEFVAL-REGISTER_ default-value
      registers_.write-u8 INTCON-REGISTER_ on-compare
      registers_.write-u8 GPINTEN-REGISTER_ (on-change | on-compare)

  /**
  Configures the electrical behavior of the INT pin.

  If $open-drain is true, the pin is an open-drain output and $active-high
    is ignored. Otherwise it is a push-pull output that is high when an
    interrupt is pending if $active-high is true, and low otherwise.
  */
  configure-interrupt-pin --open-drain/bool=false --active-high/bool=false -> none:
    mutex_.do:
      iocon := registers_.read-u8 IOCON-REGISTER_
      iocon &= ~(IOCON-ODR_ | IOCON-INTPOL_)
      if open-drain: iocon |= IOCON-ODR_
      else if active-high: iocon |= IOCON-INTPOL_
      registers_.write-u8 IOCON-REGISTER_ iocon

  /**
  Returns the pins that caused the pending interrupt.

  Bit n is set if pin n triggered the interrupt.
  */
  interrupt-flags -> int:
    return registers_.read-u8 INTF-REGISTER_

  /**
  Returns the levels of all pins at the time the interrupt occurred.

  Reading the capture clears the pending interrupt.
  */
  interrupt-capture -> int:
    return registers_.read-u8 INTCAP-REGISTER_

  configure-pin_ num/int --output/bool --pull-up/bool --value/int? -> none:
    mask := 1 << num
    mutex_.do:
      if value != null:
        olat_ = update_ OLAT-REGISTER_ olat_ mask (value != 0)
      gppu_ = update_ GPPU-REGISTER_ gppu_ mask pull-up
      iodir_ = update_ IODIR-REGISTER_ iodir_ mask (not output)

  set-pin_ num/int value/int -> none:
    mutex_.do:
      olat_ = update_ OLAT-REGISTER_ olat_ (1 << num) (value != 0)

  get-pin_ num/int -> int:
    return (read >> num) & 1

  set-pull-up_ num/int pull-up/bool -> none:
    mutex_.do:
      gppu_ = update_ GPPU-REGISTER_ gppu_ (1 << num) pull-up

  close-pin_ num/int -> none:
    pins_[num] = null

  /** Sets or clears the $mask bits in $old and writes the result if it changed. */
  update_ register/int old/int mask/int set/bool -> int:
    new := set ? old | mask : old & ~mask
    if new != old: registers_.write-u8 register new
    return new

  static check-pin_ num/int -> none:
    if not 0 <= num < PIN-COUNT: throw "INVALID_ARGUMENT"

  static check-byte_ value/int -> none:
    if not 0 <= value <= 0xFF: throw "OUT_OF_RANGE"

/**
A pin of the MCP23008.

Implements the $gpio.Pin interface, so it can be used wherever a GPIO pin is
  expected.

The MCP23008 only supports push-pull outputs and inputs with an optional
  pull-up. Pull-downs and open-drain outputs throw "UNSUPPORTED".
*/
class Pin extends gpio.PinBase:
  /** The polling interval of $wait-for. */
  static POLL-INTERVAL ::= Duration --ms=10

  owner_/Driver? := ?

  constructor.from-driver_ .owner_ num/int:
    super num

  /**
  Closes the pin, so that it can be opened again with $Driver.pin.

  The pin keeps its configuration.
  */
  close -> none:
    if not owner_: return
    owner_.close-pin_ num
    owner_ = null

  /**
  See $gpio.Pin.configure.

  A pin that is neither $input nor $output is configured as an input
    (high impedance).
  */
  configure_ -> none
      --input/bool
      --output/bool
      --pull-up/bool
      --pull-down/bool
      --open-drain/bool
      --value/int?:
    if pull-down or open-drain: throw "UNSUPPORTED"
    driver_.configure-pin_ num --output=output --pull-up=pull-up --value=value

  /** Returns the level of the pin: 0 or 1. */
  get -> int:
    return driver_.get-pin_ num

  /**
  Sets the output latch of the pin to $value (0 or 1).

  The level is only driven if the pin is configured as output.
  */
  set value/int -> none:
    driver_.set-pin_ num value

  /**
  Waits until the pin has the given $value.

  The expander is polled every $POLL-INTERVAL.
  */
  wait-for value -> none:
    while get != value: sleep POLL-INTERVAL

  /**
  Throws "UNSUPPORTED" if $value is true.

  The MCP23008 doesn't support open-drain outputs.
  */
  set-open-drain value/bool -> none:
    if value: throw "UNSUPPORTED"

  /**
  Enables the pull-up if $up is true, and disables it if $off is true.

  The MCP23008 doesn't have pull-downs, so $down throws "UNSUPPORTED".
  */
  set-pull --up/bool=false --down/bool=false --off/bool=false -> none:
    if down: throw "UNSUPPORTED"
    if up == off: throw "INVALID_ARGUMENT"
    driver_.set-pull-up_ num up

  driver_ -> Driver:
    if not owner_: throw "ALREADY_CLOSED"
    return owner_
