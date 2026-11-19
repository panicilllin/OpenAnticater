# OpenAnticater

[简体中文](README.zh-CN.md)

An open-source, native macOS app for configuring the **ANTICATER MINI** desktop volume knob — a replacement
for the vendor's Intel-only software that runs natively on Apple Silicon.

> **Unofficial project.** OpenAnticater is a community project and is not affiliated with, endorsed by, or
> supported by the maker of ANTICATER products. "ANTICATER" and other names are trademarks of their respective
> owners and are used here only to describe compatibility.

## Features

- Configure the knob's five actions: turn left, press, turn right, hold + turn left, hold + turn right
  - Keys and key combinations (type the shortcut to record it), media keys, mouse actions, or text (up to 18
    characters)
  - Warns when a shortcut is also a macOS system shortcut
- Lighting: off, white, green, marquee, RGB cycle, fast marquee
- Reads the knob's current settings automatically when connected over USB, and verifies every write by reading it
  back
- Shows the Bluetooth battery level and can notify you when it runs low
- Optional menu bar menu, open at login
- Light / dark / system appearance; English and Simplified Chinese, switchable in the app without relaunching

The knob must be connected with a **USB cable** to change its settings. Over Bluetooth or the 2.4 GHz receiver it
only sends key presses.

## Supported devices

| Device | Status |
|---|---|
| ANTICATER MINI single knob, USB `514C:8850`, firmware version 0 | Tested |
| Other models the vendor app lists (`1189` / `514C` with PIDs `8840 8842 8830–8833 8851`) | Not supported yet |

Reports from other models are welcome — see [docs/PROTOCOL.md](docs/PROTOCOL.md) for what is known about the
protocol. `swift run knobctl info` and `swift run knobctl read` are read-only and safe to run.

## Requirements

- macOS 26 or later, Apple Silicon
- Xcode 26 or later to build

## Build and run

```bash
./scripts/build-app.sh          # builds build/release/OpenAnticater.app
open build/release/OpenAnticater.app
```

Other useful commands:

```bash
swift test                      # protocol encoding/decoding tests
swift run knobctl status        # Bluetooth / receiver status and battery level (read-only)
swift run knobctl read          # print the knob's current settings (read-only)
```

The build script signs the app ad hoc, which is fine for building and running it on your own Mac. If you copy a
build to another Mac, Gatekeeper will block it; build it there instead. Distributing builds that open with a double
click requires signing and notarizing with an Apple Developer ID.

## How it works

The vendor app was analyzed for interoperability, and the configuration protocol was confirmed with read-only
queries and careful tests on real hardware. The findings are documented in [docs/PROTOCOL.md](docs/PROTOCOL.md).

OpenAnticater uses two private macOS interfaces:

- `IOPSCopyPowerSourcesByType` (IOKit) to read the knob's Bluetooth battery level
- `SLSSetGlobalHotKeyOperatingMode` (SkyLight) to pause system shortcuts while you record a shortcut, so that
  combinations like ⌃← can be recorded instead of switching desktops

Both are looked up at runtime; if a future macOS removes them, the app keeps working without those features.
Because of them, the app cannot be distributed through the Mac App Store.

## Project layout

- `Sources/KnobKit` — protocol encoding and decoding, USB HID communication, Bluetooth / receiver detection, battery
- `Sources/OpenAnticater` — the SwiftUI app
- `Sources/knobctl` — command-line debugging tool
- `Resources` — Info.plist, app icon, localizations
- `docs/PROTOCOL.md` — the reverse-engineered configuration protocol

## Disclaimer

Writing settings to the device is at your own risk. The protocol was reverse-engineered and has only been tested
on the hardware listed above. If something goes wrong, the vendor's software can restore the defaults, or use
**Settings → Restore Defaults…** in this app.

## License

Copyright © 2026 OpenAnticater contributors.

OpenAnticater is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any
later version. See [LICENSE](LICENSE).
