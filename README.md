# 360 Mouse — ZMK firmware

A wireless DIY mouse on a Pro Micro nRF52840 (SuperMini clone, nice!nano V2
compatible) with a PMW3610 optical sensor and a thumb joystick for two-axis
scrolling. It reproduces the feel of an older Arduino Pro Micro + PMW3360 build,
and adds Bluetooth, a battery and deep sleep.

| | |
|---|---|
| **Sensor** | PMW3610DM-SUDU, 1600 CPI, 250 Hz motion rate |
| **Buttons** | 6 — left, middle, right, back (MB4), forward (MB5), space |
| **Scroll** | Analog joystick: speed follows deflection, accelerates when held at the edge, locks to one axis |
| **Connection** | USB-C and Bluetooth LE, 3 pairing slots |
| **Power** | LiPo, battery level reported to the host, sleeps after 30 min idle |
| **LED** | Flickers with pointer motion, stays on while the Bluetooth menu is open |

---

## Using the mouse

### Flashing

1. Download [`firmware/zmk.uf2`](firmware/zmk.uf2).
2. Connect the mouse over USB and double-tap reset. A drive named `NICENANO` appears.
3. Copy `zmk.uf2` onto the drive. The mouse reboots on its own.

Once firmware is on the mouse you can also get into the bootloader without the
reset button: open the Bluetooth menu and press MB5 (see below).

### Buttons

| Button | Normal | In the Bluetooth menu |
|---|---|---|
| Left | Left click | Select Bluetooth slot 1 |
| Middle | Middle click | Select Bluetooth slot 2 |
| Right | Right click | Select Bluetooth slot 3 |
| MB4 | Back | **Forget** the pairing in the current slot |
| MB5 | Forward | Reboot into bootloader (for flashing) |
| Space | Space key | Switch output between USB and Bluetooth |

**Opening the Bluetooth menu:** press MB4 + Space together and hold them for
about a second. The LED stays on while the menu is open. Every menu action
closes the menu by itself.

### Pairing a new device

1. Open the Bluetooth menu and pick a free slot (left, middle or right).
2. If that slot already holds a pairing, open the menu again and press MB4 to
   clear it.
3. Pair "360 Mouse" from the host's Bluetooth settings.

When USB is plugged in, the mouse uses USB. When it isn't, the mouse uses
Bluetooth. Selecting a slot over USB only takes effect once you unplug.

> If the mouse seems dead after Space in the menu, output is probably going to a
> Bluetooth slot that isn't connected. Open the menu and press Space again.

### Scrolling

- Push the joystick a little for slow scroll, further for faster.
- Hold it fully against the edge and scroll speeds up over about 2 seconds, up to 25×.
- Whichever axis you push first takes control. The other axis is ignored until
  you push it hard (more than 800 mV of deflection), so vertical scrolling
  doesn't leak sideways.
- The joystick centre is measured at power-on. **Don't touch the stick for the
  first fraction of a second after switching on or plugging in.**

### LED

| LED | Meaning |
|---|---|
| Flickers while moving | Sensor is reporting motion |
| On steadily | Bluetooth menu is open |
| Off | Idle |

### Battery and sleep

- Charges over USB-C. Close the board's **BOOST** jumper for 300 mA charging,
  for packs of about 600 mAh and up; leave it open (100 mA) for small cells.
- Battery percentage shows in the host's Bluetooth settings. It reads 100%
  while USB is plugged in.
- Deep sleep after 30 minutes idle. Click a button to wake it.

---

## Building

### Toolchain

- Debian 13 VM, ZMK workspace at `~/Documents/zephyrproject`
- **Zephyr SDK 0.17.0.** ZMK pins Zephyr 4.1.0, and SDK 1.0.x doesn't work with it.
- Board target is `nice_nano` (revision 2.0.0). `nice_nano_v2` no longer
  exists as a separate target in Zephyr 4.1.

All modules come in through [`config/west.yml`](config/west.yml):

| Repo | Purpose |
|---|---|
| `northwestisthebest/360-zmk-mouse` | This repo: shield config, `west.yml`, prebuilt firmware |
| `northwestisthebest/zmk-analog-input-driver`, branch `360-mouse` | Forked joystick driver with all scroll behaviour and the ADC fix |
| `northwestisthebest/zmk-led-indicator` | LED module written for this mouse |
| `badjeff/zmk-pmw3610-driver` | Sensor driver, used unmodified |

### Release build (daily use)

The logging block in `360_mouse.conf` stays commented out.

```sh
. /home/nortem/.zinstaller/env.sh
cd ~/Documents/zephyrproject/zmk/app
west build -p -b nice_nano -- \
    -DSHIELD=360_mouse \
    -DZEPHYR_SDK_INSTALL_DIR=/home/nortem/zephyr-sdk-0.17.0
```

Output: `build/zephyr/zmk.uf2`.

### Debug build (USB serial logging)

Uncomment the logging block in `360_mouse.conf`, then add the
`zmk-usb-logging` snippet:

```sh
west build -p -b nice_nano -S zmk-usb-logging -- \
    -DSHIELD=360_mouse \
    -DZEPHYR_SDK_INSTALL_DIR=/home/nortem/zephyr-sdk-0.17.0
```

Read the log with this exact form; the short `tio` form doesn't work here:

```sh
sudo tio --log --log-file /tmp/analog.log /dev/ttyACM1
```

Exit with `Ctrl+t` then `q`. Keep `CONFIG_ANALOG_INPUT_LOG_DBG_RAW` off unless
you're tuning scroll. At 250 Hz it floods the link.

Name the outputs `zmk-release.uf2` and `zmk-debug.uf2` so they don't get mixed up.

### Build gotchas

- **Never pass `-DZEPHYR_EXTRA_MODULES` on the command line.** It overwrites
  ZMK's internal module list and drops `zmk/app/module`, which takes the
  `nice_nano` board and shield discovery with it (`No board named 'nice_nano'`).
- **Commit and push the driver fork before `west update`.** West checkouts
  are detached HEADs and `west update` resets them to the remote branch. In
  that checkout the remote is named `fork`, not `origin`:
  `git push fork 360-mouse`.
- **SWD flashing:** use `nrfjprog ... --sectorerase`, never `--chiperase`.
  A chip erase wipes the UF2 bootloader.

---

## Building another copy

What carries over automatically, and what needs per-copy attention:

| Item | Per copy? | What to do |
|---|---|---|
| Joystick centre | **No** | Measured at boot. The DT `mv-mid` values are only a sanity reference: a measurement more than 400 mV away from them is rejected and the DT value is used |
| Sensor rotated 180° (new PCB) | Yes | Toggle **both** `invert-x` and `invert-y` in the overlay |
| Joystick direction reversed | Yes | Toggle `invert;` on the affected `x-ch` / `y-ch` |
| Small battery (~150 mAh) | Yes | Drop `force-awake` / `force-awake-4ms-mode`; consider `sampling-hz = <100>` with `scale-divisor = <12000>` to keep scroll speed the same |
| BOOST jumper | Yes | Open for small cells (see Battery) |

> **Set sensor orientation only in devicetree.** The deprecated Kconfig option
> `CONFIG_PMW3610_ALT_INVERT_Y=y` silently overrides the DT `invert-y`
> property, so the DT setting appears to do nothing. Keep it out of `.conf`.

---

## Hardware

### Pins

| Function | Pin | Pro Micro label |
|---|---|---|
| Left click | P0.17 | D2 |
| Middle click | P0.22 | D4 |
| Right click | P0.24 | D5 |
| MB4 | P0.31 | D21 / AIN7 |
| MB5 | P0.11 | D7 |
| Space | P1.04 | D8 |
| SPI SCK | P1.13 | D15 |
| SPI MOSI | P0.10 | D16 |
| SPI MISO | P1.11 | D14 |
| Sensor NCS | P0.20 | D3 |
| Sensor MOTION | P1.15 | D18 |
| Joystick X | P0.02 | D19 / AIN0 |
| Joystick Y | P0.29 | D20 / AIN5 |
| LED | P1.00 | D6 |

Buttons switch to GND (internal pull-ups, 5 ms debounce).

### PMW3610 wiring

- **3-wire SPI.** MOSI and MISO join at the sensor's SDIO pin (pin 2), with a
  series resistor on the MOSI leg (500 Ω works; 1–2.2 kΩ is typical).
- **NRESET (pin 7) tied to VDDIO.** If it floats you get random resets and
  pointer jumps when you touch the board. The driver doesn't drive this pin.
- **VDD (pin 14) = 1.8 V from an LDO** (XC6206-class), with 100 nF right at the pin.
- **VDDIO (pin 6) = 3.3 V.**
- **CP/CN (pins 12/13):** charge-pump capacitor.
- SPI runs at 2 MHz, the datasheet maximum, and is stable.

### Don't power the sensor from a zener

At power-up the sensor needs up to 60 mA, with a supply rise under 1 ms and
under 100 mVp-p of noise. A zener with a series resistor can't do that:

- 220 Ω from 3.3 V gives about 6.8 mA, roughly a ninth of what's needed. The
  sensor fails self-reset or behaves erratically.
- A smaller resistor pushes the zener up its soft knee, and VDD can exceed the
  2.2 V absolute maximum.
- A bulk capacitor slows the rise past 1 ms, and self-reset never completes.

Use an LDO.

### Enameled wire

Every signal here is enameled wire, and it has caused two multi-hour hunts:

- **Incompletely stripped joints** give intermittent high resistance that
  looks like "works sometimes".
- **A scraped spot mid-run** makes an invisible high-resistance contact. Here
  MOTION touched the LED anode and held the LED half-lit at 2.7 V while its
  driving pin read 0 V.

After any rework, check each signal for continuity against its neighbours.

### Battery sensing

Read through VDDH (`zmk,battery-nrf-vddh`): no divider, no ADC pin. The
nice!nano board files have no battery node, so the overlay declares one.

---

## Tuning reference

### Sensor

```dts
spi-max-frequency = <2000000>;
cpi = <1600>;
force-awake;
force-awake-4ms-mode;
x-input-code = <INPUT_REL_Y>;   /* sensor mounted rotated 90° */
y-input-code = <INPUT_REL_X>;
invert-x;
```

- **Polling:** in normal run mode the PMW3610 samples every ~8 ms (125 Hz).
  `force-awake` + `force-awake-4ms-mode` gives 250 Hz (verified), which is the
  ceiling for this sensor. The PMW3360 in the Arduino build did 1000 Hz. There
  is no run-rate register.
- **force-awake** stops the sensor from entering its rest modes, so it draws
  more current on battery as well as on USB. It's fine with a large cell;
  drop it on small ones.
- **CPI** goes in steps of 200, up to 3200.

### Joystick: driver constants

At the top of `src/analog_input.c` in the fork (branch `360-mouse`):

| Constant | Value | Effect |
|---|---|---|
| `AI_CURVE_BLEND` | 1 | Response curve: 0 linear … 4 fully quadratic |
| `AI_ACCEL_RAMP_MS` | 2000 | Time to reach full hold boost |
| `AI_ACCEL_BOOST` | 25 | Speed multiplier once fully ramped |
| `AI_ACCEL_EDGE_MV` | 20 | Acceleration triggers within this distance of either ADC rail |
| `AI_ADC_TOP_MV` | 3300 | Measured upper rail |
| `AI_DZ_SETTLE` | 5 | In-deadzone samples needed before the accumulator re-arms |
| `AI_CAL_ENABLE` | 1 | Measure the centre at boot |
| `AI_CAL_SAMPLES` | 50 | Samples in the boot median |
| `AI_CAL_WINDOW` | 400 | Max mV between the measured centre and DT `mv-mid` before the measurement is rejected |
| `AI_CROSS_DZ_MV` | 800 | Deadzone of the axis that doesn't own scroll; 0 disables axis lock |

> The accumulator line `acc[i] += sign * av * ch_cfg.scale_multiplier;`
> appears **twice** in a row. That doubles scroll speed, so the effective
> divisor is 15000, not the 30000 in DT. All tuning was done with it doubled.
> If you remove the duplicate, halve `scale-divisor` to keep the same feel.

### Joystick: devicetree

```dts
sampling-hz = <250>;
```

| Property | X (AIN0) | Y (AIN5) |
|---|---|---|
| `mv-mid` | 1563 (reference only; calibrated at boot) | 1624 |
| `mv-min-max` | 1450 | 1400 |
| `mv-deadzone` | 200 | 200 |
| `scale-divisor` | 30000 | 30000 |
| `invert` | yes | yes |
| `input-code` | `INPUT_REL_HWHEEL` | `INPUT_REL_WHEEL` |

How the knobs interact:

```
rate      ≈ (deflection − deadzone) × sampling_hz / scale_divisor
max rate  ≈ mv-min-max × sampling_hz / scale_divisor   (before hold boost)
```

- `scale-divisor` scales slow and fast speeds together.
- `mv-min-max` sets the ratio between slowest and fastest.
- `AI_CURVE_BLEND` decides how that range spreads across stick travel.
- Raising `mv-min-max` moves the clamp toward the rails and shrinks the zone
  where acceleration can trigger.

### Keymap timing

The combo `timeout-ms` is **800**. At 50 ms the two presses (measured 208 ms
apart) fell through as normal clicks. The hold-tap `tapping-term-ms` is 1000:
that's the "hold for a second".

---

## Driver changes (fork)

Everything here lives in `zmk-analog-input-driver`, branch `360-mouse`, except
the battery driver patch.

1. **ADC channel offset.** The joystick and the VDDH battery driver both used
   SAADC channel 0, so the battery driver measured the joystick's X pin and
   reported 0%. The joystick channels are shifted up by one, and the AIN
   mapping is unchanged. Any ZMK build that combines this module with
   battery reporting hits this bug.
2. **Pre-scale accumulator.** Stock code scales, then truncates, so small
   deflections produce nothing and the minimum rate is one tick per sample.
   The fork accumulates raw deflection and emits whole ticks, keeping the
   remainder.
3. **Sign-correct priming.** The accumulator is primed one count below
   threshold in the direction of travel, so the first tick fires right away
   in both directions. Plain priming + C truncation-toward-zero made down
   take 1.9× more deflection than up.
4. **Deadzone settle.** The accumulator re-arms only after `AI_DZ_SETTLE`
   consecutive centre samples, so noise at the deadzone edge doesn't fire ticks.
5. **Rail-proximity acceleration.** "Pushed all the way" is detected by
   distance to the ADC rails, independent of `mv-min-max` and of rest drift.
6. **Boot calibration.** Takes the median of 50 samples at boot, with a sanity
   window against DT `mv-mid`. Output is muted while sampling.
7. **Axis lock.** The first axis out of its deadzone owns scroll. The other
   axis gets a deadzone of `AI_CROSS_DZ_MV` until the owner returns to centre.
   This needs both channels in **one** device (`anin0`).

**Not in any repo:** `zmk/app/module/drivers/sensor/battery/battery_nrf_vddh.c`
is modified in the local ZMK checkout. A copy of the diff is in
[`patches/`](patches/).

Also required, and set in the shield `.conf`: `CONFIG_SENSOR=y`. The analog
module uses `CONFIG_SENSOR_INIT_PRIORITY` without selecting `SENSOR`, so without
it linking fails with `Undefined initialization levels used`.

### LED indicator module

Drives one GPIO directly. It's lit when the configured layer is active **or**
the watched pointing device reported motion within `activity-hold-ms`. No
keymap bindings are needed.

```dts
led_indicator: led_indicator {
    compatible = "zmk,led-indicator";
    gpios = <&gpio1 0 GPIO_ACTIVE_HIGH>;
    indicate-layer = <1>;
    activity-device = <&trackball>;
    activity-hold-ms = <60>;
};
```

ZMK's backlight subsystem was tried first and abandoned. Brightness is clamped
to [1, 100], so there's no real off, and its state persists to NVS and
overrides the firmware default after boot.

### Bootloader entry

`&bootloader` needs GPREGRET retention nodes in the overlay, not just Kconfig.
Without them the chip resets straight back into firmware, with a brief red
blink. See the end of `360_mouse.overlay`.

### Settings persistence

`CONFIG_FLASH`, `FLASH_MAP`, `NVS`, `SETTINGS_NVS` and
`MPU_ALLOW_FLASH_WRITE` are all required. Without them, Bluetooth bonds vanish
on every reboot.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Enumerates over USB, `bNumInterfaces 0`, nothing works | `CONFIG_ZMK_USB=y` missing |
| `Incorrect product id 0xff` | Sensor never answered: power or NRESET problem |
| `spi_nrfx_spim: Timeout waiting for transfer complete` | Sensor dead or over-voltaged |
| Axes swap intermittently | SPI framing error; X/Y low bytes are adjacent in the burst read |
| Pointer jumps when you touch a pin | Floating NRESET |
| Battery stuck at 0% | ADC channel collision (driver change 1) |
| Battery stuck at 100% | No battery node, or USB is plugged in |
| BT menu combo does nothing | Combo timeout too short |
| DT `invert-y` has no effect | Leftover `CONFIG_PMW3610_ALT_INVERT_Y` in `.conf` |
| Scroll stronger in one direction | Truncation-toward-zero priming (driver change 3) |
| Scroll drifts when untouched | Stick touched during boot calibration; power-cycle hands-off |
| Sideways scroll leaks during vertical scroll | Raise `AI_CROSS_DZ_MV` |
| `No board named 'nice_nano'` | `-DZEPHYR_EXTRA_MODULES` on the command line |
| LED half-lit at rest | Enamel-wire short from MOTION into the LED anode |
| Driver edits have no effect after `west update` | Fork changes weren't pushed; west reset the checkout |

When a theory predicts something you can check, check it before acting on it.
The scroll asymmetry survived three plausible explanations that the logs
refuted. Logging trigger points in both directions found it in one pass.

---

## Outstanding work

1. **Joystick mode switch** (MCLK + MB4). Mode 1: dual scroll. Mode 2: vertical
   scroll on one axis, volume up/down at the extremes of the other. Splitting the
   axes into two devices would break axis lock (driver change 7) and collide
   the driver's per-loop-index static arrays, so it's likely better done
   inside the single device.
2. **Right-click toggle** (MCLK + MB5). Press toggles, release is ignored. No
   stock ZMK behaviour does this.
3. **Shield variants** for multiple copies: a shared `.dtsi` plus small
   per-copy overlays (orientation, force-awake, sampling rate).
4. **Measure BLE report rate** and verify sleep and wake on battery.

## Abandoned approaches

- **ZMK backlight for the LED.** See the LED indicator module above.
- **`te9no/zmk-input-processor-keybind`** for rate-based scroll. `&msc` feeds
  a timer-driven accumulator, so short taps were lost: 149 presses gave 11
  scroll events. Solved in the driver instead.
- **Voltage divider on AIN7 for the battery.** Unnecessary once the channel
  collision was found.
- **Zener 1.8 V supply.** See Hardware.
- **PMW3360 breakout as a PMW3610 carrier.** Different pinout.
