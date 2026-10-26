# Yunzii Control

A small Mac app for the **YUNZII YZ98** keyboard (wired, USB-C). Works on Apple Silicon and Intel Macs running macOS 13 or newer.

- **Lighting**: pick a built-in effect, colour, brightness and speed. Saved on the keyboard, so it survives unplugging and works on any computer.
- **Per-key colours**: paint individual keys and save them to the keyboard.
- **Top row**: choose whether the top row sends F1–F12 or Mac media keys (brightness, Mission Control, dictation, Apps, Spotlight, music, volume), with Fn for the other. Uses the keyboard's **Win** switch position with a Mac-style ⌘/⌥ layout written to the keyboard; Mac mode is left untouched as a fallback.
- **Live** (top-right decal over Home/End/PgUp/PgDn; needs the app running, menu bar is enough):
  - Zoom mute light: red while muted, green while unmuted.
  - Meeting alert: a blue sweep from 1 minute before a calendar meeting until 2 minutes after it starts.
  - Optional purple pulse while any other app uses the mic or camera.
- Shows the keyboard's Mac/Win switch position. On **Mac** the keyboard uses its built-in Mac layout (media top row); on **Win** it uses the layout from the Top row tab.

## Install (no building)
1. Open `dist/YunziiControl.dmg` and drag **YunziiControl** into **Applications**.
2. Open it. macOS will block it the first time because it isn't from an identified developer: go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Allow **Input Monitoring** when asked (needed to talk to the keyboard), then click **Reopen app**.
4. For the Live features: allow **Accessibility** (reads Zoom's mute button) and **Calendars** (meeting alert). Your work calendar must appear in the macOS Calendar app.
5. Optional: turn on **Launch at login** in the Live tab.

Settings can only be changed over the USB-C cable, not 2.4 GHz or Bluetooth. Other keyboards are detected and left untouched.

## Build from source
```sh
xcode-select --install          # once, if you don't have Apple's Command Line Tools
./build.sh                      # → build/YunziiControl.app (universal)
pip3 install dmgbuild           # once, only for the installer
./make_dmg.sh                   # → build/YunziiControl.dmg
```
Before building your own copy, change `CFBundleIdentifier` in `Info.plist` to something of your own.

**Tip:** without a signing certificate the app is signed ad-hoc and works fine, but macOS forgets its permissions after every rebuild. To avoid that, create a self-signed code-signing certificate named `YunziiControl Local Signing` in your login keychain; `build.sh` uses it automatically.

## Undo
- In the app: **Restore first-launch settings…** puts back the lighting the keyboard had when the app first saw it (snapshot in `~/Library/Application Support/YunziiControl/`).
- Or from Terminal: `python3 tools/writeled.py <backup.bin>` with a backup made by `python3 tools/readled.py`.

See `AGENTS.md` for the protocol details and how the code is organised.
