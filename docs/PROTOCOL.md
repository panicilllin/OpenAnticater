# ANTICATER MINI configuration protocol

[简体中文](PROTOCOL.zh-CN.md)

For the single-knob ANTICATER MINI (Bluetooth name `ANTICATER_MINI`). Derived from disassembling the vendor's
macOS app `ANTICATER.app` (2025-08-20 build, x86_64, Qt 5.12, hidapi, symbols not stripped) and from read-only
queries against a real device. Items marked **verified** were confirmed on hardware.

## Device and interfaces

| Connection | VID:PID | Can be configured |
|---|---|---|
| USB cable | `514C:8850` | Yes. Interface 0 is a vendor-defined channel (usage page `0xFF00`, report ID 3 + 64 bytes in both directions); interface 1 is a regular keyboard / mouse / consumer-control device |
| Bluetooth | `05AC:022C` (presents itself as an Apple keyboard) | No |
| 2.4 GHz receiver | `514C:4155` | No |

PIDs the vendor app recognizes: `8842 8840 8830 8831 8832 8833 8850 8851` under VID `1189` or `514C`.

Packets below omit the leading report ID `03`; device replies include it.

## Query device shape `FB FB FB` (verified)

Reply: `03 FB <key count> <knob count> <version> …`. The tested unit replies `00 01 00`: no keys, one knob,
version 0. Firmware version ≥ 10 uses a different flow with 65-byte records and per-key RGB, which this app does
not implement.

## Read one layer `FA 0F 03 <layer>` (verified)

Layers 1–3. The device sends 24 records (slots 1–24, in no fixed order):

```
03 FA <slot> <layer> <type> 00 00 00 00 00 <count> <data…>
```

## Write one slot `FD <slot> <layer> <type> 00×5 <count> <data…>` (verified)

Same layout as the read reply with the command byte `FA` replaced by `FD`. Old firmware uses only the first 50
bytes; the rest is zero. After each layer, the vendor app sends the commit packet `FD FE FF` and waits one second.

### Slots

The vendor app's "0 keys + 1 knob" layout (`Set_Keyboard_0add1`) maps the five knob actions to:

| Action | Slot |
|---|---|
| Turn left | 16 |
| Press | 17 |
| Turn right | 18 |
| Hold + turn left | 19 |
| Hold + turn right | 21 |

Slot 20 is unused; slots 1–15 are for models with keys.

Verified: temporarily writing "Volume Up" to slot 16 on layer 1 made a physical left turn change the volume, so
slot 16 is the left turn, and a write followed by a commit takes effect immediately without replugging.

### Types and data

| Type | Meaning | Data |
|---|---|---|
| `01` | Keys | count n (1–18), then n pairs of `modifiers, HID usage`; with n > 1 they are typed in sequence |
| `02` | Media | count 1, then a Consumer-page usage (16-bit little-endian), e.g. `E9 00` for Volume Up |
| `03` | Mouse | count 1, then `modifiers, buttons, X, Y, wheel`; buttons 1 left / 2 right / 4 middle; wheel ±1 |
| `05` | Delay | not implemented |

Modifier bits: `01` Control, `02` Shift, `04` Option, `08` Command.

## Lighting `FE B0 <layer> 08 00×5 01 00 <lighting byte>` (verified)

Written to slot 0, sent together with the slot records before the commit.

The vendor app treats the lighting byte as `color << 4 | mode` (colors 1–7: red, orange, yellow, green, cyan, blue,
purple; modes 0–5: off, clockwise, counterclockwise, alternate, jump, blink; it fills in color 5 when none is
chosen). **The tested unit (firmware version 0) only looks at the low 4 bits; the high 4 bits have no effect.**
Observed on hardware:

| Low 4 bits | Actual effect |
|---|---|
| 0 | Off |
| 1 | White |
| 2 | Green |
| 3 | Marquee |
| 4 | Red / green / blue cycle |
| 5 | Fast marquee (factory default) |
| 6 | Similar to 5; not offered by the vendor app or this app |

Full bytes tested: `00`, `10` off; `01`, `11`, `31`, `51` white; `13` marquee; `15` fast marquee.

Old firmware does not answer the lighting read request (`FA B0 …`), so lighting cannot be read back.

## Which layer is used

All three layers can be read and written. On the tested unit the knob behaved according to layer 1, while layers
2 and 3 held vendor defaults (volume, play / pause, track skip), so the firmware uses layer 1. The single-knob model
has no layer-switch key; to be safe this app writes the same settings to all three layers.
