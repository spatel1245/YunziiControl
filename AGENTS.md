# AGENTS.md — YunziiControl

Native macOS app (SwiftUI, no Xcode project) that configures a **YUNZII YZ98** keyboard over USB and drives live lighting on the 4 LEDs under its top-right decal. Read this before changing anything; the hardware facts below were verified on a real YZ98 and are not documented anywhere else.

## Build / run / ship
- Requires only Apple Command Line Tools (`xcode-select --install`). No Xcode, no SwiftPM.
- `./build.sh` → `build/YunziiControl.app`, universal (arm64 + x86_64), min macOS 13. Signs with keychain identity `YunziiControl Local Signing` if present, else ad-hoc.
- `./make_dmg.sh [app]` → `build/YunziiControl.dmg` (needs `pip3 install dmgbuild`; set `DMGBUILD_PYTHON` to pick an interpreter).
- Release: bump `CFBundleShortVersionString` + `CFBundleVersion` in `Info.plist`, `./build.sh`, copy app to `/Applications`, `./make_dmg.sh`.
- No unit tests. Verify on hardware: build, launch, use the in-app **Preview** buttons, and `tools/` scripts.

## Toolchain gotchas (will bite you)
- CLT lacks the SwiftUI macro plugin: **`@State` does not compile**. Use `@StateObject` + a small `ObservableObject` (see `LightingState`, `PerKeyState`). `@Published`, `@ObservedObject`, `@StateObject`, `@Environment` are fine. Don't use `@Observable`/`@AppStorage` either.
- Large SwiftUI view expressions hit "unable to type-check in reasonable time" — split into subviews (see `KeyView`).
- Compile flags: `-parse-as-library -swift-version 5` (Swift 6 strict concurrency is off on purpose). Threading model: UI/state on main; all HID I/O on `KeyboardModel.io` serial queue.
- `ld: warning ... libswiftCompatibilityPacks.a missing x86_64` is harmless (link succeeds; x86_64 slice runs under Rosetta).

## Source map (`Sources/`)
| File | Owns |
|---|---|
| `HID.swift` | Protocol constants (`YZ`), `YZDevice` (feature-report framing, read/write/liveFrame), `LED` block parsing/editing + effect table |
| `Model.swift` | `KeyboardModel`: IOHIDManager hot-plug, load/reload, snapshot of original settings, all writes (`perform` → write → read-back verify), live-frame send, `liveBase()` |
| `Live.swift` | `LiveEngine`: 25 Hz render loop for the decal; Zoom mute via Accessibility, mic/camera via CoreAudio/CoreMediaIO, meetings via EventKit, launch-at-login |
| `Layout.swift` | `YZ98Layout` physical key geometry (key id = `col*6+row`), `Keycodes` (dormant remap support), `TopRow` (Win-mode Mac layout + top-row codes) |
| `Views.swift` | All SwiftUI: tabs Lighting / Per-key / Top row / Live, header, permission screen, menu bar content. `RemapView` exists but is **not shown** (see below) |
| `App.swift` | `AppState` singletons, app delegate (starts kb + live; keeps running when window closes), `WindowGroup` + `MenuBarExtra` |

## Hardware protocol (USB 258A:010C, model id 0xB3)
- Vendor HID collection: usage page `0xFF00`, usage `0x01`, interface 1. Open **non-exclusive** (`kIOHIDOptionsTypeNone`). Opening needs **Input Monitoring** (else `kIOReturnNotPermitted` 0xE00002E2).
- Every transfer = 520-byte **feature report 0x06**: `[06, cmd, sub, 0, total, index, size_lo, size_hi, payload…]`, ≤512 payload bytes per packet. Read = SetFeature header with `cmd|0x80`, wait 20 ms, GetFeature 520, payload at byte 8.
- Commands: `0x02` sub1 len6 → model id at payload[5] · `0x03` key table (sub = layer 0–3, 512 B, 4 B/key) · `0x04` LED settings block (128 B) · `0x06` per-key colours (sub 0, 384 B = R[126] G[126] B[126] + 6 pad) · `0x08` live frame (378 B interleaved RGB, **not stored**).
- LED block: valid only if `b[126..127] == 5A A5`. `b[0]` = hardware **Mac/Win switch** (1 = Mac), `b[9]` = 1 iff per-key mode, `b[10]` = effect id, per-effect slot at `0x3A + 2*slot`: `[brightness 0–4, speed<<4 | colour]`. Slot = index in `LED.effects` (order matters). Colour nibble 0–6 = palette, 7 = random. Per-key effect id = 21.
- LED/key index = `col*6 + row`. Decal LEDs (Home, End, PgUp, PgDn) = **90, 96, 102, 108**. Fn key = index 59.
- Key-table entry (4 B): `[0x00, modbits, 0, usage]` keyboard key (+modifiers) · `[0x02, 0, hi, lo]` consumer/media usage · `0x07…`/`0x08…` firmware functions (Fn layer) · `0x0D…` Fn.
- **Combo quirk:** modifiers come from interface 0 (boot report) but the key from interface 1 (NKRO), and the key arrives *first*, so macOS often sees a plain key (Ctrl+↑ becomes ↑). Prefer single consumer usages: Mission Control `0x29F`, Apps/Launchpad `0x2A2`, dictation `0xCF`. Cmd+Space (Spotlight) happens to work.
- Brightness codes `0x6F/0x70` only affect the built-in/Apple displays (macOS limitation), not external monitors.
- Live frames override the whole board while streaming; stop sending and the keyboard returns to its saved effect. Fine at 25 Hz.

## Invariants — do not break
1. **Read-modify-write** the LED block; never write a block you didn't just read and validate. Preserve `b[0]` (switch) on restore.
2. Writes only when `status == .ready`, which requires model id in `YZ.supportedModels` (0xB3). Other Sinowealth boards reuse this VID/PID and **have been bricked** by blind writes elsewhere — keep the gate.
3. Every write is followed by a read-back compare; surface failure to the user.
4. Never change the Fn key entry (index 59) in any layer.
5. Don't send live frames while `busy` (settings write in flight) — `sendLiveFrame` already guards with `frameInFlight`.

## Verified behaviour / known limits
- **Mac mode ignores the key table entirely** (built-in layout; Alt→⌘, Win→⌥, top row = media). Remaps only apply with the switch on Win. General remapping was removed from the UI (code dormant); the **Top row** tab instead writes a Mac-style Win-mode layout (`TopRow.macModifiers` + F1–F12 or `TopRow.macMedia` in layer 0, the other set in layer 1). That's how users get F1–F12 by default.
- Fn+CapsLock "white" is a RAM-only override (doesn't touch the block).
- Unverified: brightness max (assumed 4), effect names (taken from the AULA driver that shares this firmware), per-key brightness slot.
- Zoom state is read from Zoom's **Meeting** menu items "Mute audio"/"Unmute audio" (Zoom 7.x, English UI). Locale or Zoom UI changes break it.
- Meetings come from EventKit, so the Exchange calendar must be synced into macOS Calendar.

## Permissions (TCC)
Input Monitoring (keyboard I/O), Accessibility (Zoom), Calendars (meetings). Grants are bound to the code signature: ad-hoc builds lose them on every rebuild; a stable signing identity keeps them. `tccutil` can't be run from sandboxed agents — ask the user.

## Live engine priority (`LiveEngine.render`)
Preview › Zoom muted (red) / unmuted (green) › meeting alert (blue bouncing comet, −60 s to +120 s around start) › optional "other call" purple pulse (mic/camera in use) › nothing (stop streaming).

## `tools/` (Python 3.9+, ctypes IOKit, no deps)
`iokit_hid.py` (helpers + `require()`), `readled.py` (dump + back up LED block), `writeled.py [backup.bin]` (set Static white, or restore a backup), `snap.py NAME [OTHER]` (snapshot all areas into `tools/snaps/`, diff), `livetest.py` (30 s decal animation), `keylisten.py [secs]` (prints media codes, F-keys and shortcut combos only, never ordinary typing), `setkey.py LAYER INDEX HEX8` (set one key-table entry, Fn-guarded). Terminal needs Input Monitoring.
