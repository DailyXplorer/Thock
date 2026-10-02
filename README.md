# Thock

Thock plays a mechanical keyboard sound on every keystroke, in every app on your Mac. It lives in the menu bar. It has no main window and no Dock icon.

- macOS 14 or later, Swift 6, SwiftUI and AppKit, no third-party dependencies.
- App Sandbox and Hardened Runtime enabled.
- A single permission: **Input Monitoring**. Thock never asks for Accessibility.
- No network access. No keystroke is stored or logged.

## Installation

Requirements: Xcode 27 and XcodeGen (`brew install xcodegen`).

```sh
make build              # generates Thock.xcodeproj, builds and signs; build/Thock.app points to the product
make run                # builds, stops the running instance, launches build/Thock.app
make test               # unit tests (Swift Testing)
make reset-permissions  # forgets the Input Monitoring permission (tccutil), the only place that touches TCC
```

Other targets:

| Target | Purpose |
|---|---|
| `make stop` | Quits Thock. |
| `make logs [SINCE=2m]` | Thock's log, plus the TCC decisions and sandbox denials that concern it. No keycode ever appears in it. |
| `make verify-signature` | Checks the signature, the entitlements and the designated requirement. |
| `make cpu [IDLE=20 BENCH=20]` | CPU at idle, then during the synthetic typing benchmark (`BENCH=0`: idle only, no sound). |
| `make latency` | Launches Thock with the latency histogram on (menu > Diagnostics). |
| `make probe` / `make probe-hid` | Logs the type, `stateID` and PID of each event (never the keycode). The second one compares with an HID tap. |
| `make render [PACK=mxblue LABEL=after]` | Renders a fast typing sequence offline (100 then 140 words/min, overlapping keys, a Backspace burst, five keys at once) with the real audio engine. Writes `build/renders/LABEL_PACK.wav` (48 kHz, a link into DerivedData, outside iCloud) and prints the peak, clipped samples, cut sounds and timing error. |
| `make preview [PACK=cream]` | Plays a few keystrokes from a bundled pack with `afplay` (letters on several rows, space, return), without launching Thock. Defaults to `holypanda`. |
| `make packs` | Downloads the kbsim recordings again and rewrites the bundled pack files that changed. Only this script touches the network, never the app. |
| `make icon` | Regenerates the app icon. |
| `make clean` | Deletes the generated project and DerivedData. |

DerivedData lives in `~/Library/Developer/Xcode/DerivedData/Thock-make`, outside `~/Documents`. Under a synced `~/Documents`, the bundle picks up extended attributes and `codesign` fails. `build/Thock.app` is a stable symbolic link to the product. `make run` always launches that path, so TCC keeps a single entry.

## Input Monitoring permission

On first launch, Thock opens a welcome window that explains the permission. The “Open System Settings” button adds Thock to the list (`CGRequestListenEventAccess`), then opens the Privacy & Security > Input Monitoring pane directly (`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`). All that is left is to turn Thock on.

Thock polls `CGPreflightListenEventAccess()` once per second while the permission is missing. As soon as it is granted, capture starts, without a relaunch. The tap is only created after a positive preflight. Otherwise, `tapCreate` would show the system prompt before the explanation.

If the permission is revoked while Thock runs, the tap watchdog (every 3 s) detects it. Thock then stops the tap, forgets the held keys and reopens the welcome window. When the permission comes back, capture restarts by itself.

## Signing

TCC ties the Input Monitoring permission to the app's designated requirement. So every build must be signed with the same stable identity. With a certificate, the requirement looks like this:

```
identifier "io.github.dailyxplorer.thock" and certificate leaf = H"<certificate SHA1>"
```

It only depends on the bundle id and the certificate, so it stays the same from one build to the next: you grant the permission once, and it survives rebuilds. `make verify-signature` prints it.

**Default: ad hoc signing.** `Config/Signing.xcconfig`, tracked by git, signs ad hoc (`CODE_SIGN_IDENTITY = -`) so the project builds without any setup. An ad hoc signature has no certificate. Its designated requirement is the `cdhash`, the fingerprint of the binary, which changes on every build. macOS then treats each build as a new app and asks for the permission again. For regular use, set a stable identity.

**Setting your identity.** Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`. This file is ignored by git and included by `Config/Signing.xcconfig` (`#include?`). Two options:

- **Self-signed certificate.** Open Keychain Access > Certificate Assistant > Create a Certificate. Pick a name, the identity type “Self-Signed Root” and the certificate type “Code Signing”. Then read its SHA1 with `security find-identity -v -p codesigning`, and put it in `CODE_SIGN_IDENTITY`:

  ```
  CODE_SIGN_STYLE = Manual
  CODE_SIGN_IDENTITY = <certificate SHA1>
  DEVELOPMENT_TEAM =
  OTHER_CODE_SIGN_FLAGS = --timestamp=none
  ```

  Referencing the certificate by its SHA1 rather than its name avoids any ambiguity if two certificates share the same name.

- **Apple Development.** With a developer account in Xcode:

  ```
  CODE_SIGN_STYLE = Manual
  CODE_SIGN_IDENTITY = Apple Development
  DEVELOPMENT_TEAM = <team identifier>
  OTHER_CODE_SIGN_FLAGS = --timestamp=none
  ```

You can also override it for a single build:

```sh
make build CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=XXXXXXXXXX
```

**No password prompt.** When access to the key is allowed for `codesign`, signing doesn't ask for a password. The app never touches the keychain, and the build neither creates nor unlocks one.

Changing identity changes the designated requirement: you have to grant the permission one last time, possibly after `make reset-permissions`.

**Upgrading from an earlier build.** The bundle id changed to `io.github.dailyxplorer.thock`, so macOS sees an existing install as a different app: run `make reset-permissions` and grant Input Monitoring again. Settings and imported packs from the old id are not carried over.

## Usage

**Menu bar menu.** The icon is a keyboard. It turns into a crossed-out speaker while muted, and a keyboard with an ellipsis while the permission is missing. The menu contains:

- the On/Off switch and the current mute reason (turned off, microphone in use, excluded app frontmost, system output muted);
- a discreet indicator when secure input is on (`IsSecureEventInputEnabled()`, read every 2 s with a 1 s tolerance);
- the volume, the pack, the audio output (system default or a specific device), spatialization and mouse sounds;
- the “Include Synthetic Keystrokes” and “Launch at Login” options (`SMAppService.mainApp`);
- diagnostics, collapsed by default: keycode-free counters, audio state and latency measurement.

**Global shortcut.** By default, ⌃⌥⌘K turns Thock on or off. It goes through Carbon `RegisterEventHotKey`, with no permission. Change it in Settings > General: click, then type the combination, or press Esc to cancel. The shortcut must include ⌘ or ⌃, because macOS 15 rejects combinations of ⌥ or ⌥⇧ alone. If another app already owns the combination, Thock keeps the previous one and says so.

**Automatic mute** (Settings > Mute). Each rule can be turned off separately:

- **Microphone in use.** A listener on `kAudioDevicePropertyDeviceIsRunningSomewhere` of the default input, re-subscribed when the default input changes. This property covers both directions of a device. When the input is also Thock's output (AirPods, USB headset), it would always be true because of Thock itself. In that case, Thock asks each audio process whether it is recording (`kAudioProcessPropertyIsRunningInput`, macOS 14.2+). No input stream is ever opened.
- **Excluded app frontmost.** A list of bundle ids, filled from the open apps or by choosing an `.app`. Thock follows `NSWorkspace.didActivateApplicationNotification`. Opening Thock's menu or settings doesn't lift the mute for the app underneath.
- **System output muted.** The mute state of the default output, tracked by a Core Audio listener.

While muted, the audio engine keeps running and the state machine keeps tracking keys. Unmuting costs nothing and no phantom release is played.

All settings are persisted in `UserDefaults`.

## Pack format

A pack is a folder:

```
MyPack/
├── pack.json            {"name": "My pack", "author": "Me", "license": "CC-BY-4.0", "source": "https://…"}
├── alpha_down_r0.caf    row 0: Esc and function keys
├── alpha_down_r1.caf    row 1: digits
├── alpha_down_r2.caf    row 2: Tab, Q W E R T Y (A Z E R T Y)
├── alpha_down_r3.caf    row 3: Caps Lock, A S D F (Q S D F), Return
├── alpha_down_r4.caf    row 4: Shift, Z X C V (W X C V), then space, ⌘ ⌥ ⌃ and arrows
├── alpha_up_1.caf
├── space_down_1.wav
└── …
```

- File names, either:
  - `category_direction_variant`: `alpha_down_1.caf`, played on every row;
  - `category_direction_rROW` or `category_direction_rROW_variant`: `alpha_down_r2.caf`, `alpha_down_r2_3.wav`, played on that row only.
- Extensions: `caf`, `wav`, `aiff`, `aif`. `source` is optional in `pack.json`.
- Categories: `alpha` (letters and digits), `space`, `enter`, `backspace`, `tab`, `modifier`, `arrow`, `punctuation` and `mouse`. Directions: `down` for the press, `up` for the release.
- Rows: the physical row of the key, derived from its virtual keycode, so it is the same on AZERTY, QWERTY and ISO. The ISO `<` key (keycode 10) is on row 4. The split follows kbsim, where the space row shares the row 4 sample.
- For a key, Thock takes the files for its row, otherwise the variants without a row, otherwise the nearest recorded row. A category with no file at all falls back to `alpha` in the same direction, for the same row. A pack in the row-less `alpha_down_1.caf` format therefore works as before.
- At least one `alpha_down` file is required, with or without a row.
- On load, Thock mixes to mono and resamples. It then trims each file 1 ms before the first sample at 20 dB below its own peak, and after the last one at 45 dB below it. Short fades avoid clicks at both cuts. Finally, it normalizes the whole pack to -1 dBFS peak. The threshold is relative because the recordings differ in level by up to 20 dB and have an MP3 noise floor around -50 dBFS: an absolute threshold triggered on the noise and left up to 20 ms of silence before the attack. A single gain for the whole pack keeps the intended differences, for example a space bar louder than a letter.
- Every keystroke varies continuously: playback speed within ±1.5 % (±2.5 % for a release), gain between -2.5 dB and the recorded level (-4 dB for a release), and part of the sound softened by a 3 kHz low-pass, up to 30 % (60 % for a release). Releases vary more because kbsim only has one file per switch for them. When a key has several files, it never plays the same one twice in a row.

**Import.** Drag the folder onto the list in Settings > Packs, or click “Import Folder…” (sandbox: read access to the chosen folder only). Thock copies `pack.json` and the recognized audio files into `~/Library/Containers/io.github.dailyxplorer.thock/Data/Library/Application Support/Packs/`. It then decodes the copy: a pack that wouldn't play is rejected with the reason, and nothing stays on disk. The imported pack is listed with the bundled packs, then selected. An imported pack can be deleted from the same list.

**Bundled packs.** These are real mechanical switch recordings, taken from kbsim (see Credits) and converted by `make packs` to 16-bit mono CAF at 48 kHz:

The last column gives each switch's reputation, not a listening verdict: compare them with `make preview PACK=<id>`.

| Pack | Switch | Reputation |
|---|---|---|
| Holy Panda (default) | tactile | strong bump, round keystroke |
| NovelKeys Cream | linear | muted, deep, smooth |
| Cherry MX Brown | light tactile | dry and discreet, close to an office keyboard |
| Cherry MX Black | heavy linear | crisp and clean |
| Cherry MX Blue | clicky | high-pitched click (kbsim has no dedicated space or return: these keys reuse row 4) |
| Kailh Box Navy | heavy clicky | thick, loud click |
| Alps SKCM Blue | vintage clicky | dry, metallic click |
| Topre | electro-capacitive | deep, muffled “thock” |

Each pack has one press sample per row, a generic release, and dedicated files for space, Return and Backspace. The other keys (Tab, modifiers, arrows, punctuation) use their row's sample, as in kbsim. Left out to keep the characters distinct: `alpaca`, `turquoise`, `blackink` and `redink`, four more linears, and `buckling` (IBM buckling spring), one more clicky. None of the files in the eight packs kept is defective: duration, peak and noise floor were measured for each one.

## Technical choices

**`.cgSessionEventTap` rather than `.cghidEventTap`.**

- Apple documents the listen-only tap under the sandbox with the Input Monitoring permission. The session level is the normal case for that combination. The HID level has always been associated with root or Accessibility.
- The session tap only sees the login session. After fast user switching, Thock doesn't hear the other session.
- Secure input is respected without doing anything.
- The latency difference with the HID level is assumed to be in the tens of µs, negligible next to the audio buffer. It is not measured. `make probe-hid` lets you compare.

**Hot path.** The tap callback, on a dedicated thread with its own run loop, copies a few fields into a C11 SPSC ring, without allocating or logging. It then wakes the audio queue through `DispatchSourceUserDataAdd`. That queue filters, reduces the state machine and pushes a 32-byte command into a second SPSC ring, without switching threads or calling AVFoundation. The render block of an `AVAudioSourceNode` (`Sampler`) reads that ring and mixes up to 32 voices. The engine stays warm. The IO buffer is 128 frames.

**Custom sampler rather than 32 `AVAudioPlayerNode`s.** Measured with `make render`: `scheduleBuffer(at: nil)` starts the sound on the next render, or one to two cycles later, depending on an internal race. The same keystroke time doesn't give the same start from one run to the next. In fast typing, the gap between two sounds drifted by up to 7 ms from the gap between the two keystrokes. Scheduling to the exact frame needs one `AVAudioTime` per sound, hence an allocation. The `Sampler` instead places each sound exactly one cycle plus 1 ms after its keystroke, with variable-speed Hermite interpolation. It only steals a voice when none is free, and then takes the one with the least sound left. A limiter without lookahead keeps the output under -1 dBFS. The render block takes no lock and allocates nothing.

## Measurements

Rough orders of magnitude, which vary with the machine and the audio output. The tools to reproduce them are `make cpu`, `make latency` and `make render`.

| Measurement | Order of magnitude |
|---|---|
| CPU at idle (app running, engine at 48 kHz, no typing) | ≈ 0 % |
| CPU under sustained simulated typing (17 events/s, `--bench-typing`) | ≈ 0 to 1 % |
| Software latency, CGEvent timestamp → scheduled sound | p50 of a few tens of µs, p99 under 0.1 ms |
| Keystroke → sound start, offline render at 128 frames | constant, one cycle plus 1 ms (≈ 3.7 ms), no interval drift |
| Output latency reported by Core Audio | the device's: a few ms wired, over 150 ms for Bluetooth headphones |
| Allocations in our code (pipeline drain, 200 events) | 0, checked by the tests |

**Pitch variation.** One `AVAudioUnitVarispeed` per voice was tried and dropped: in an offline render, 32 idle voices cost more than ten times as much CPU with it. The `Sampler` varies the speed itself, through interpolation.

The benchmark is synthetic: it pushes events into the real ring without going through the tap. The perceived wired latency is estimated at about 7 ms (the `Sampler`'s 3.7 ms lead, plus one output cycle and the device). This is an estimate, not an end-to-end measurement.

## Known limitations

- **Secure input.** In a password field, or when an app turns on secure input (Terminal with “Secure Keyboard Entry”, some password managers), macOS stops sending keystrokes to the tap. Thock goes silent and the menu says so. This is intended, Thock doesn't work around it.
- **Bluetooth.** Latency is imposed by the headphones (Bluetooth headphones often report over 150 ms). No Thock setting changes that. Wired or on the built-in speakers, the delay is a few ms.
- **Allocations.** Nothing allocates between the tap and the `Sampler`'s ring, nor in its render block: measured with a `malloc_logger` hook. AVAudioEngine's `renderOffline` itself allocates 2 blocks per 64 cycles, whether there are 12 voices to mix or none.
- **Microphone on a shared device.** When the default input is also Thock's output, detection goes through the audio processes, which requires macOS 14.2. On macOS 14.0 and 14.1, the rule doesn't trigger in that case.
- **Synthetic keystrokes.** The filter keeps `eventSourceStateID == 1` (HID state). That is the expected value for hardware. It still needs confirming with `make probe` on each kind of keyboard and injector.
- **CGEvent timestamp unit.** It is assumed to be in `mach_absolute_time` ticks. The “Timestamps off the host clock” counter in Diagnostics will check this during real typing. If the assumption is wrong, Thock still plays every sound.
- **Launch at Login.** `SMAppService.mainApp` registers the bundle at its actual location, here inside DerivedData. After `make clean`, you have to turn the option on again.

## Privacy

- Thock receives keyboard and mouse events in listen-only mode (`.listenOnly`). It can neither modify nor inject them.
- Only the event type, keycode, modifiers, auto-repeat flag, source and timestamp are copied, then forgotten after the sound. Nothing is written to disk.
- No keycode is ever logged, even in probe mode. `RawInputEvent` has no text description.
- No network entitlement, no telemetry.
- Entitlements: `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-only` (pack import, choosing an app to exclude). In Debug, Xcode adds `get-task-allow`. Reading the microphone state works without `com.apple.security.device.audio-input`: checked under the sandbox, with no TCC trace in the log.
- The only persisted data are the settings (`UserDefaults`) and the imported packs.

## Troubleshooting

- **Capture doesn't start even though the permission is granted.** Use “Relaunch Thock” in the menu. If the permission seems tied to an old build, run `make reset-permissions`, then grant it again.
- **No sound.** Check the mute reason in the menu, then the diagnostics (“Audio stopped” or counters stuck at zero). `make logs` shows the engine state.
- **Manual tests.** See [MANUAL_TESTS.md](MANUAL_TESTS.md).

## Credits

- **Bundled pack sounds**: switch recordings from [kbsim](https://github.com/tplai/kbsim) by Thomas Lai, under the MIT license (`src/assets/audio` folder). Thock converts them to mono CAF at 48 kHz, then trims and normalizes them on load. The per-row split of the samples also follows kbsim. Full license text: [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).
- Thock uses neither the name, the icon nor the sounds of Klack.
