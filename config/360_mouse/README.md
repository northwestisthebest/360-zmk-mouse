# 360 Mouse — ZMK firmware

A wireless custom mouse built on a Pro Micro nRF52840 (SuperMini clone,
nice!nano V2 compatible), recreating an earlier Arduino Pro Micro build with
feel parity as the goal.

- **Sensor:** PMW3610DM-SUDU optical
- **Buttons:** 6 (left / middle / right / MB4 / MB5 / space)
- **Scroll:** dual-axis joystick, rate-based with hold acceleration
- **Connectivity:** USB HID + BLE, automatic endpoint selection
- **Power:** 1200 mAh LiPo with battery reporting and deep sleep
- **Indicator:** single LED — BT layer state plus pointer activity

---

## Repositories

| Repo | Purpose |
|---|---|
| `northwestisthebest/360-zmk-mouse` | Shield config, `west.yml`, compiled firmware |
| `northwestisthebest/zmk-analog-input-driver` (branch `360-mouse`) | Forked analog driver — scroll behaviour and ADC fixes |
| `northwestisthebest/zmk-led-indicator` | Purpose-written LED indicator module |

The ZMK workspace itself lives at `~/Documents/zephyrproject` and is not
committed. One patch lives only in that checkout — see
[Local patches](#local-patches).

---

## Hardware

### Board

Pro Micro nRF52840 "SuperMini" clone. Pin-compatible with nice!nano V2 except
P1.01 / P1.02 / P1.07, which are broken out to their own pads.

Build target is `nice_nano` (revision 2.0.0). Since Zephyr 4.1 merged the
board definitions, `nice_nano_v2` no longer exists as a separate target.

### Pin assignments

| Function | Pin | Notes |
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
| Sensor MOT | P1.15 | D18 |
| Joystick X | P0.02 | D19 / AIN0 |
| Joystick Y | P0.29 | D20 / AIN5 |
| Indicator LED | P1.00 | D6 |

All buttons are wired to GND, active low, with internal pull-ups and 5 ms
debounce.

### PMW3610 wiring

The sensor uses a 3-wire SPI variant: **MOSI and MISO are joined at the
sensor's SDIO pin (pin 2)**, with a series resistor on the MOSI leg to limit
bus contention during reads. 500 Ω works; 1–2.2 kΩ is the more standard range.

Required connections beyond the SPI bus:

- **NRESET (pin 7) tied to VDDIO.** Leaving it floating causes intermittent
  resets mid-transaction — the driver deprecated reset-pin control and relies
  on software reset over SPI, so nothing drives this pin.
- **VDD (pin 14) = 1.8 V**, with 100 nF decoupling as close to the pin as
  possible.
- **VDDIO (pin 6) = 3.3 V**, matching the nRF's logic level.
- **CP/CN (pins 12/13)** charge-pump capacitor.

SPI clock is 250 kHz. The datasheet maximum is 2 MHz, but a burst read is only
~88 bits and motion reports arrive every 4–8 ms, so there is an order of
magnitude of headroom. The low speed was chosen during signal-integrity
debugging and left in place.

### Power supply — the hard-won lesson

**Do not power the sensor from a zener shunt.** The datasheet requires up to
60 mA transient during VDD ramp with a rise time under 1 ms, and allows only
100 mVp-p supply noise across 10 kHz–50 MHz. A zener with a series resistor
cannot deliver that:

- 220 Ω from 3.3 V sources ~6.8 mA — roughly a ninth of the ramp requirement.
  The sensor either fails to complete its power-up self-reset or behaves
  erratically.
- Halving to 110 Ω raises current but also climbs the zener's I-V curve.
  Low-voltage zeners have soft knees, and VDD can end up above the 2.2 V
  absolute maximum.
- Adding a bulk capacitor to a high-impedance supply pushes the RC rise time
  past the 1 ms limit, so the internal self-reset never completes.

Use a proper LDO. An XC6206-class fixed 1.8 V part in SOT-23 sources 200 mA+
and starts in microseconds.

### Battery

1200 mAh protected LiPo. The board's **BOOST** jumper raises charge current
from 100 mA to 300 mA, a safe 0.25C at this capacity.

Battery sensing uses VDDH (`zmk,battery-nrf-vddh`) — no divider, no ADC pin.
The nice!nano board files declare no battery node, so the overlay declares it.

Reports ~74% at 4.04 V on battery, and 100% on USB (VDDH sees ~4.7 V from the
USB rail, above full charge).

### Enameled wire

Every signal on this build is enameled wire, and it has caused two separate
multi-hour debugging sessions:

- **Incompletely stripped joints** give intermittent high resistance that
  presents as "works sometimes".
- **A scraped-through spot mid-run** produces a high-resistance accidental
  contact — invisible, and it does not behave like a hard short. The MOTION
  line touching the LED anode held that node at 2.7 V while the driving pin
  itself measured 0 V.

Do a continuity sweep of each signal against its neighbours after any rework.

---

## Firmware

### Toolchain

- Debian 13 (Trixie) VM, VS Code with the Zephyr Workbench extension
- **Zephyr SDK 0.17.0** — ZMK pins Zephyr 4.1.0, which requires exactly this
  SDK. SDK 1.0.x targets Zephyr 4.4 and will not work.
- Workspace at `~/Documents/zephyrproject`

### Build

```sh
. /home/nortem/.zinstaller/env.sh
cd ~/Documents/zephyrproject/zmk/app
west build -p -b nice_nano -S zmk-usb-logging -- \
    -DSHIELD=360_mouse \
    -DZEPHYR_SDK_INSTALL_DIR=/home/nortem/zephyr-sdk-0.17.0
```

Output: `build/zephyr/zmk.uf2`

Flash by double-tapping reset and dragging the `.uf2` onto the `NICENANO`
drive, or over SWD with:

```sh
nrfjprog --family NRF52 --program build/zephyr/zmk.hex --sectorerase --verify
```

Use `--sectorerase`, never `--chiperase`, or you lose the UF2 bootloader.

> **Do not pass `-DZEPHYR_EXTRA_MODULES` on the command line.** It clobbers the
> value ZMK sets internally, dropping `zmk/app/module` and with it the
> `nice_nano` board definition and shield discovery. All three modules are in
> `west.yml`, so no extra flags are needed.

### Debug logging

USB CDC serial via the `zmk-usb-logging` snippet:

```sh
sudo tio --log --log-file /tmp/analog.log /dev/ttyACM1
```

Exit tio with `Ctrl+t` then `q`.

Keep `CONFIG_LOG_DEFAULT_LEVEL=1` and enable only the module you care about.
`CONFIG_ANALOG_INPUT_LOG_DBG_RAW=y` at 250 Hz across two channels is ~500 lines
per second, which floods the CDC link and drops everything else — turn it off
unless you are actively tuning scroll.

RTT over J-Link also works and functions on battery power, which USB logging
cannot:

```sh
JLinkRTTLogger -Device NRF52840_XXAA -If SWD -Speed 4000 -RTTChannel 0 /tmp/rtt.log
```

---

## Modules

### zmk-analog-input-driver (fork)

badjeff's driver with substantial local changes — see
[Local patches](#local-patches) for what and why.

### zmk-led-indicator

Purpose-written. Owns a GPIO directly and lights it when *either* the
configured layer is active *or* the watched pointing device reported motion
within the hold window.

```dts
/ {
    led_indicator: led_indicator {
        compatible = "zmk,led-indicator";
        gpios = <&gpio1 0 GPIO_ACTIVE_HIGH>;   /* P1.00 */
        indicate-layer = <1>;
        activity-device = <&trackball>;
        activity-hold-ms = <60>;
    };
};
```

No keymap bindings required — the layer half hooks ZMK's
`zmk_layer_state_changed` event, so entering or leaving the layer by any means
drives the LED automatically.

**Written because ZMK's backlight subsystem is the wrong tool for an
indicator.** Brightness is clamped to a minimum of 1 (`BRT_START=0` is rejected
at build time), so there is no true off via brightness. The state persists to
NVS and overrides `ON_START=n` about a second after boot. `BRT_STEP` defaults
to 20, so the resolution is coarse. And `BL_ON`/`BL_OFF` toggle *state* while
`BL_SET` sets *brightness*, which interact confusingly.

---

## Local patches

Six changes live outside the config repo. A `west update` that fast-forwards a
module will silently discard uncommitted work — commit and push before
updating.

Five are in the analog driver fork. **One is not in any repo:**
`zmk/app/module/drivers/sensor/battery/battery_nrf_vddh.c` is modified in the
ZMK checkout only. A copy of that diff is in `patches/`.

### 1. `CONFIG_SENSOR=y` (shield `.conf`)

The analog input module's Kconfig does `select ADC` but never `select SENSOR`,
while the driver uses `CONFIG_SENSOR_INIT_PRIORITY` in its
`DEVICE_DT_INST_DEFINE`. With the sensor subsystem off that symbol is
undefined, the macro expands with an empty priority, and the linker fails with
`Undefined initialization levels used`.

Upstream bug, worth reporting.

### 2. ADC channel offset

**The subtle one.** Both drivers configured ADC **channel 0**:

| | analog input | battery VDDH |
|---|---|---|
| gain | `ADC_GAIN_1_6` | `ADC_GAIN_1_2` |
| input | `AnalogInput0` (P0.02) | `VDDHDIV5` |
| acquisition | default | 40 µs |

The joystick reconfigures channel 0 a hundred times a second, so the battery
driver's once-a-minute read was measuring the joystick's X pin. It reported
2585 mV → 0%, which looks like a plausible reading rather than an error.

Fix: shift the analog driver's channel index up by one while keeping the AIN
mapping intact.

```c
uint8_t ain = ch_cfg.adc_channel.channel_id;
uint8_t channel_id = ain + 1;
...
.channel_id = channel_id,
.input_positive = SAADC_CH_PSELP_PSELP_AnalogInput0 + ain,
```

Also upstream-worthy: any ZMK build combining this module with battery
reporting hits it, and the symptom points nowhere near the cause.

### 3. Pre-scale accumulation

Stock behaviour scales *then* accumulates, using integer division. Any
deflection where `v * mult / div` truncates to zero produces no output at all,
and the smallest non-zero output is one unit per sample — 100 scroll ticks per
second at 100 Hz. The Arduino's slowest scroll was ~2.5/sec.

The patch accumulates unscaled deflection and emits whole units as they cross
the divisor, keeping the remainder:

```
acc += deflection_mV
out  = acc / divisor
acc -= out * divisor
```

Rate then scales linearly with deflection, with no truncation floor.

### 4. Symmetric priming and deadzone settling

Two bugs found by measurement, both in the accumulator.

**Instant first tick.** The Arduino fires immediately on leaving centre,
because its `previousMillis` is stale from the last scroll — the interval test
is already satisfied. A zero-initialised accumulator instead costs
`divisor / (v × sampling_hz)` seconds before the first tick: 0.4 s at small
deflection. Fixed by priming the accumulator to just below threshold.

**Direction symmetry.** C integer division truncates *toward zero*, so priming
to `+(divisor − 1)` puts the positive direction one count from firing while the
negative direction starts on the wrong side and must travel `2 × divisor`.
Measured: up triggered at 226 mV, down at 423 mV — a 1.9× asymmetry, and
changing `mv-mid` by 112 mV moved neither number, which is what ruled out a
centring error. Fixed by priming with the sign of travel.

**Deadzone settling.** Priming on every in-deadzone sample meant noise
crossing the boundary fired a tick each time — up to 50/sec from a stationary
stick. `AI_DZ_SETTLE` requires N consecutive in-deadzone samples before
re-arming.

After these, up/down triggers measured 186 / 249 mV — within session-to-session
rest variation.

### 5. Rail-proximity hold acceleration

The Arduino ramps scroll rate when the stick is held at full deflection
(`interval = 20 - 20*(hold/1500)`). Reproducing that needs a trigger that means
"pushed all the way", and tying it to a percentage of `mv-min-max` does not
work: the value is clamped to `mv_min_max` before the test, so a threshold
above 100% is unreachable, and the two axes have different usable spans.

The trigger is now proximity to the ADC rails, which do not move with rest
drift:

```c
if (mv <= AI_ACCEL_EDGE_MV || mv >= (AI_ADC_TOP_MV - AI_ACCEL_EDGE_MV)) {
```

This decouples acceleration from `mv-min-max` entirely — full scroll speed is
reached at the clamp, acceleration engages closer to the mechanical stop.

Keep `AI_ACCEL_EDGE_MV` below the smallest clamp-to-rail distance across all
four directions, or acceleration will engage *before* full speed on the
tightest one. X-down is the binding constraint.

### 6. Boot calibration (present, disabled)

`AI_CAL_ENABLE` is **0** — the devicetree `mv-mid` values are used.

The calibration samples each channel for 200 ms at boot, takes the median, and
accepts it only within `AI_CAL_WINDOW` of the configured value so a stick held
at power-on cannot poison it. It works, but it was measuring a resting position
systematically ~20 mV from where the stick settles *after being used*, and the
current 200 mV deadzone makes that error irrelevant.

Measured mechanics, for reference: undisturbed rest noise is ±3 mV, but
mechanical return after release varies 27 mV (AIN0) to 39 mV (AIN5), and
settling takes 10–30 ms. Session-to-session rest has been seen to move 40 mV.
Calibration can only fix long-term drift; the deadzone covers per-release
variance.

If re-enabled, a slow continuous re-centring — nudging the midpoint during
confirmed rest — would be more robust than a one-shot at boot.

### Bootloader retention (overlay, not a patch)

`&bootloader` needs devicetree nodes as well as Kconfig, and the `nice_nano`
board files provide none. Without them the chip resets but the UF2 bootloader
sees a plain reset and boots straight through — a brief red blink is the only
sign.

```dts
&gpregret1 {
    adafruit_boot_retention: retention@0 {
        compatible = "zephyr,retention";
        status = "okay";
        reg = <0x0 0x1>;
    };
};

/ {
    magic_mapper {
        compatible = "zmk,bootmode-to-magic-mapper";
        status = "okay";
        #address-cells = <1>;
        #size-cells = <1>;
        boot_retention: retention@0 {
            compatible = "zephyr,retention";
            status = "okay";
            reg = <0x0 0x1>;
        };
    };
    chosen {
        zephyr,boot-mode = &boot_retention;
        zmk,magic-boot-mode = &adafruit_boot_retention;
    };
};
```

---

## Tuning

### Driver constants

At the top of `src/analog_input.c` in the fork. Verify against the source —
these are the values as last recorded.

| Constant | Value | Effect |
|---|---|---|
| `AI_CURVE_BLEND` | 0 | 0 = linear, 4 = fully quadratic response |
| `AI_ACCEL_RAMP_MS` | 2000 | Time to reach full hold boost |
| `AI_ACCEL_BOOST` | 25 | Multiplier once fully ramped |
| `AI_ADC_TOP_MV` | 3300 | Measured pot upper rail |
| `AI_ACCEL_EDGE_MV` | — | Distance from either rail that triggers acceleration |
| `AI_DZ_SETTLE` | 5 | In-deadzone samples before re-priming |
| `AI_CAL_ENABLE` | 0 | 0 = use devicetree `mv-mid` |

`AI_ACCEL_PCT` is left in the source but unused since patch 5.

### Devicetree

```dts
sampling-hz = <250>;
```

| Property | X (AIN0) | Y (AIN5) |
|---|---|---|
| `mv-mid` | 1563 | 1624 |
| `mv-min-max` | 1450 | 1400 |
| `mv-deadzone` | 200 | 200 |
| `scale-divisor` | 30000 | 30000 |
| `input-code` | `INPUT_REL_HWHEEL` | `INPUT_REL_WHEEL` |

Measured extremes: both axes sweep 0–3318 mV. Rest sits at roughly 1514–1563
(X) and 1610–1652 (Y) depending on session.

**How the knobs interact:**

```
rate          = (deflection - deadzone) × sampling_hz / scale_divisor
max rate      = mv-min-max × sampling_hz / scale_divisor
accel trigger = within AI_ACCEL_EDGE_MV of 0 or AI_ADC_TOP_MV
```

`scale-divisor` scales both ends together and cannot change the ratio between
minimum and maximum speed. That ratio comes from `mv-min-max`, and how it is
distributed across travel comes from `AI_CURVE_BLEND`.

Raising `mv-min-max` moves the clamp closer to the rails, shrinking the window
in which acceleration lives. X-down has the least room.

### Sensor axis orientation

The sensor is mounted rotated 90°. Corrected by swapping the report codes in
the overlay and inverting one axis:

```dts
x-input-code = <INPUT_REL_Y>;
y-input-code = <INPUT_REL_X>;
```
```conf
CONFIG_PMW3610_ALT_INVERT_Y=y
```

### Settings persistence is mandatory

Without these, `CONFIG_SETTINGS_NONE=y` is selected and nothing reaches flash.
BLE bonds, profile selection and endpoint preference all vanish on reboot,
presenting as "pairs fine, never reconnects until you delete the device on the
host."

```conf
CONFIG_FLASH=y
CONFIG_FLASH_MAP=y
CONFIG_NVS=y
CONFIG_SETTINGS_NVS=y
CONFIG_MPU_ALLOW_FLASH_WRITE=y
```

---

## Keymap

### Layer 0 — default

| Position | Button | Binding |
|---|---|---|
| 0 | left | `&mkp LCLK` |
| 1 | middle | `&mkp MCLK` |
| 2 | right | `&mkp RCLK` |
| 3 | MB4 | `&mkp MB4` |
| 4 | MB5 | `&mkp MB5` |
| 5 | space | `&kp SPACE` |

### Layer 1 — Bluetooth

Entered by holding **MB4 + space** together for ~1 s, via a combo feeding a
hold-tap. Every binding performs its action and returns to layer 0 in a single
press, so no cancel key is needed. The indicator LED is lit throughout.

| Position | Button | Action |
|---|---|---|
| 0 | left | select BT profile 0 |
| 1 | middle | select BT profile 1 |
| 2 | right | select BT profile 2 |
| 3 | MB4 | clear pairing on active profile |
| 4 | MB5 | enter bootloader |
| 5 | space | toggle USB / BLE output |

Combo `timeout-ms` is **300**. The original 50 ms was too tight — logs showed
the two presses landing 208 ms apart, so the candidate timed out and both
buttons fell through to their normal bindings.

On USB, `BT_SEL` changes the profile used once unplugged but has no immediate
effect. `BT_CLR` *is* immediate and destroys a bond silently. `OUT_TOG` can
route output to a BLE profile that isn't connected, making the mouse appear
dead until toggled back.

---

## Connectivity

Endpoint selection is automatic and needs no configuration — ZMK prefers USB
when connected and falls back to BLE otherwise.

BLE pointer movement feels less smooth than USB because reports go out at the
negotiated connection interval (typically 7.5–15 ms) rather than USB's 1 kHz
polling. **A BT 5.x adapter is noticeably smoother than BT 4.0** — test the
adapter before chasing this in firmware.

Deep sleep at 30 minutes idle, light idle at 30 s.

The 32.768 kHz crystal workaround (`CONFIG_CLOCK_CONTROL_NRF_K32SRC_RC`) was
tested and is **not needed** on this board.

---

## Power budget

| Consumer | Estimate |
|---|---|
| PMW3610 (run, incl. laser) | 0.60 mA |
| nRF52840 + BLE | ~1.0 mA |
| Analog driver polling | ~1–3 mA |
| **Total active** | **~2.6–4.6 mA** |

At 1200 mAh that is roughly 300+ hours of continuous use, so battery life is
not a design constraint here.

The analog driver's README warns that its poll mode has relatively high power
consumption and is not recommended for wireless builds. That is accurate — it
samples continuously regardless of stick movement and is the largest single
consumer. On a smaller cell, lowering `sampling-hz` would be the first lever.

PMW3610 rest-mode currents for reference: Rest1 36 µA, Rest2 16 µA, Rest3 7 µA,
shutdown 3 µA.

---

## Debugging playbook

Symptoms encountered and what they meant:

| Symptom | Cause |
|---|---|
| `bNumInterfaces 0`, enumerates but nothing works | `CONFIG_ZMK_USB=y` missing — Zephyr's USB stack up, but ZMK never registered an HID interface |
| `Incorrect product id 0xff` | Sensor never drove SDIO — power or reset problem |
| `spi_nrfx_spim: Timeout waiting for transfer complete` | Sensor not responding at all; suspect over-voltage or damage |
| Axes swapping intermittently | SPI framing, not optics — `Delta_X_L` and `Delta_Y_L` are adjacent bytes in the burst read, so one byte of misalignment transposes them |
| Pointer jump when touching a pin | Capacitive coupling into a floating high-impedance node (NRESET) |
| Battery pinned at 0% with plausible mV | ADC channel collision (patch 2) |
| Battery pinned at 100% | No battery node configured at all |
| Combo does nothing | Timeout too short; check `filter_timed_out_candidates` in the log |
| Scroll only on position change | `report-on-change-only` set — the driver README notes mouse input does not need it |
| `ZMK_BACKLIGHT_BRT_START` rejected | Backlight brightness is clamped to `[1, 100]`; 0 is not representable |
| `No board named 'nice_nano'` | `-DZEPHYR_EXTRA_MODULES` on the command line clobbered ZMK's own module list |
| LED dim at rest, brighter on motion | Not a duty cycle — a multimeter averages. Here it was a scraped enamel wire shorting MOTION to the LED anode |

### A note on method

Several of these were diagnosed by measuring rather than reasoning, after the
reasoning produced wrong answers. The scroll asymmetry in particular survived
three plausible explanations — mismatched pot spans, a bad calibration
midpoint, and supply-rail loading — all of which the logs refuted. Logging
trigger points in both directions found it in one pass.

When a theory predicts something checkable, check it before acting on it.

### Sensor optical alignment

The PMW3610 exposes **SQUAL** (register 0x06), a measure of valid features
visible in the current frame, maximum 361. It peaks at the correct Z-height, so
it can tune sensor height empirically rather than with calipers. Target is
2.2 / 2.4 / 2.6 mm from lens reference plane to surface. SQUAL, shutter and
pixel values all arrive in the motion burst read already.

---

## Outstanding work

1. **Joystick mode switch** (MCLK + MB4) — mode 1 dual scroll, mode 2 vertical
   scroll on one axis with volume up/down past 90% / below 10% on the other.
   Requires splitting the two ADC channels into separate devices with separate
   listeners so a layer-conditional processor can apply to one axis only. Note
   that the driver's static arrays are indexed by loop position and would
   collide between two single-channel devices — index by channel id instead.
2. **Right-click toggle** (MCLK + MB5) — press toggles state, release ignored.
   No stock ZMK behaviour does this; `zmk,input-processor-behaviors` is worth
   testing before writing a custom one. The LED indicator module is a natural
   home for it if custom C is needed.
3. **Sleep verification** — configured but never tested.

Both remaining features could in principle be done at OS level instead. The
argument for firmware is portability: the mouse is used over BLE with more than
one host, and anything implemented in the OS stops existing elsewhere. The
right-click toggle in particular is *easier* in firmware — on Wayland there is
no global input grab, so an OS-level version means a uinput daemon that grabs
the device and re-emits modified events.

## Abandoned approaches

- **ZMK backlight for the indicator LED** — brightness clamped to a minimum of
  1, state persisted to NVS overriding the firmware default, coarse steps.
  Replaced with a purpose-written GPIO module.
- **`te9no/zmk-input-processor-keybind`** — quantises pointer input into
  discrete key events, which looked right for rate-based scroll. In practice
  `&msc` is not a one-shot: it adjusts a speed accumulator that a periodic
  timer converts to scroll. With `tap-ms = 10` most activations completed
  before the timer ticked — logs showed 149 binding presses producing 11 scroll
  events. Solved by patching the driver instead.
- **`zmk,battery-voltage-divider` on AIN7** — planned fallback when VDDH read
  0%, would have required moving MB4 and adding a 2 MΩ / 806 kΩ divider.
  Unnecessary once the ADC channel collision was found.
- **Zener + series resistor for 1.8 V** — see the power section.
- **PMW3360 breakout as a PMW3610 carrier** — different pinout, so untouched
  traces connect pins to nets designed for a different part.
