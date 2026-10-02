# Manual tests

Run these on a `make run` build, with Thock's menu open whenever a counter is involved (Diagnostics, expanded). The counters never show a keycode. Tick each box once the expected result has been observed.

## 0. Setup

- [ ] `make build` then `make verify-signature`: `Authority=` shows the certificate chosen in `Config/Signing.local.xcconfig`, `flags=0x10000(runtime)`, `designated => identifier "io.github.dailyxplorer.thock" and certificate leaf = H"<certificate SHA1>"`.
- [ ] No password prompt during the build or at launch.

## 1. Permission and onboarding

- [ ] **First launch without permission** (`make reset-permissions`, then `make run`): the “Welcome to Thock” window opens. The menu bar icon shows a keyboard with an ellipsis. No system prompt appears before the click.
- [ ] **Granting without a relaunch**: “Open System Settings” opens Privacy & Security > Input Monitoring, where Thock is already listed. Turn Thock on. Within about 1 s, the window switches to “All set” and the menu shows “Active”, without relaunching the app. If System Settings offers “Quit & Reopen”, choose “Later”: capture must work anyway.
- [ ] **The permission survives a rebuild**: edit a source file (or `make clean`), then `make run`. The menu shows “Active” right away, with no prompt or password.
- [ ] **Revoking then restoring while the app runs**: turn Thock off in Input Monitoring. Within 3 s at most, the welcome window reopens and the icon changes. Type: no sound. Turn it back on: “All set” comes back without a relaunch and the sounds return.

## 2. State machine (Presses / Releases counters)

- [ ] **Delete held for 5 s**: a single press sound and a single release sound (+1 / +1), despite auto-repeat.
- [ ] **Fast typing** (a sentence typed quickly, overlapping keys): as many presses as releases, no sound missing to the ear.
- [ ] **Modifier combinations**: left ⇧, right ⇧, left and right ⌘, left and right ⌥, ⌃, Fn and Globe each give +1 / +1. Left ⇧ held, then right ⇧ pressed and released: the right ⇧ release sounds, then the left ⇧ release sounds in turn. ⌘C, ⌘⇧4: one sound per key.
- [ ] **Caps Lock**: a press followed by a short release on every press, both when turning it on and off.
- [ ] **`<` key** (ISO, left of Z on QWERTY, left of W on AZERTY) and punctuation keys: they make a sound.

## 3. Audio

- [ ] **A sound on every keystroke** in several apps (Notes, Safari, Terminal without secure input).
- [ ] **Sound quality**: `make preview PACK=<id>` to compare the 8 packs outside the app (`holypanda`, `cream`, `mxbrown`, `mxblack`, `mxblue`, `boxnavy`, `bluealps`, `topre`), then type with each one in Thock, with spatialization on and then off. Note which ones to remove or to keep as the default.
- [ ] **Rows**: type F5, 5, T, G, B with a kbsim pack. Each row has its own sample, and the same key repeated varies slightly in pitch, level and timbre. On AZERTY, `<` (left of W) sounds like the bottom row.
- [ ] **Attack**: with Topre then MX Brown (the kbsim clips with the longest leading silences), the sound must start as fast as with Cream. No click at the end of a sound, even on the MX Brown space bar, which is cut abruptly in the original recording.
- [ ] **Old saved pack**: on the first launch of this version, the old “Feutré” pack saved in the settings no longer exists. Thock selects Holy Panda and the menu shows it checked.
- [ ] **Switching packs while typing**: open Settings > Packs, type continuously with one hand and click another pack with the other. No lasting dropout, no crash, the new pack sounds from the next keystroke.
- [ ] **Real latency**: `make latency`, type for a minute, read p50 and p99 in Diagnostics (expected: p99 < 2 ms). “Timestamps off the host clock” must not increase with every keystroke, otherwise the assumption about the timestamp unit is wrong. Also listen on the built-in speakers or wired output to judge the perceived delay (≈ 7 ms estimated).
- [ ] **CPU on wired output**: choose the built-in speakers as the system output, then `make cpu`. Expected: < 1 % at idle, < 3 % during the benchmark.
- [ ] **Unplugging then reconnecting AirPods while typing**: no crash. The sound comes back in under a second on the new output and “Rebuilds” increases.
- [ ] **Chosen output then disconnected**: choose the headphones in “Output”, then turn them off. The sound moves to the default output and the menu shows “Disconnected Device”. Turn them back on: the sound returns to them.
- [ ] **Instruments Allocations** (optional, the automated measurement covers this): profile Thock while typing and filter on `io.github.dailyxplorer.thock.audio`. No allocation may appear while typing, neither on that queue nor on the audio render thread.

## 4. System

- [ ] **Sleep and wake**: put the Mac to sleep, wake it, type. The sound comes back without relaunching the app, and no key stays “stuck” (no phantom release on the first press).
- [ ] **Session lock**: lock the screen (⌃⌘Q), unlock, type. The sound comes back. The password typed on the lock screen must not make a sound.
- [ ] **Password field**: click into a password field (Safari, System Settings). The menu shows “Secure input is on” within 2 s at most and typing is silent. When leaving the field, the indicator disappears and the sound comes back.
- [ ] **Fast user switching** (if a second account exists): switch, come back, type. The sound comes back.

## 5. Interface and settings

- [ ] **Global shortcut**: ⌃⌥⌘K from any app turns Thock off (crossed-out speaker icon, menu shows “Off”), then back on.
- [ ] **Changing the shortcut**: Settings > General, click ⌃⌥⌘K, type ⌃⌥⌘J. The new shortcut works, the old one does nothing. Type ⌥A alone: rejected with the message “must include ⌘ or ⌃”. Esc cancels. Quit and relaunch Thock: ⌃⌥⌘J is kept. “Default” restores ⌃⌥⌘K.
- [ ] **Shortcut already taken**: try a combination reserved by another app or by macOS. Thock keeps the previous shortcut and shows the error.
- [ ] **Microphone mute (FaceTime call)**: start a FaceTime call (or a voice memo). The menu shows “Muted: the microphone is in use” and typing is silent. Hang up: the sound comes back. Repeat with AirPods as both input and output: same result.
- [ ] **Microphone rule turned off**: Settings > Mute, uncheck the microphone rule. During the call, Thock makes sound.
- [ ] **Excluded app**: Settings > Mute > “Add Open App” > pick an app (Notes). Bring Notes to the front: muted, with “Notes is frontmost” in the menu. Open Thock's menu from Notes: the mute stays. Switch to another app: the sound comes back. Do the same with “Choose App…” and an `.app` from /Applications. Remove the app from the list: the sound comes back in Notes.
- [ ] **System output muted**: mute the Mac (mute key). The menu shows “the audio output is muted” and Thock goes silent. Unmute: the sound comes back. Uncheck the rule: Thock then only follows the device volume.
- [ ] **Chosen output muted**: choose headphones in “Output” while the system output stays on the speakers. Mute the speakers: Thock keeps sounding in the headphones. Mute the headphones: muted. Switch back to “System Default Output” while the headphones are muted: the sound comes back with no other action.
- [ ] **Unreadable pack**: import a pack, quit Thock, corrupt `alpha_down_1` in `~/Library/Application Support/Packs/<pack>`, relaunch and choose that pack. The menu and Settings > Packs show the error, and the selection goes back to the pack actually playing.
- [ ] **Synthetic**: with an injector (Keyboard Maestro, text expansion), “Ignored” increases and the presses don't. Check “Include Synthetic Keystrokes”: the presses increase.
- [ ] **stateID / PID probe**: `make probe`, type on the built-in keyboard, a USB keyboard, a mouse, with an injector and through Screen Sharing. Note the `stateID` and `pid` for each source. Expected for hardware: `stateID=1 accepted=true`. If an injector also gives `stateID=1`, note its `pid`.
- [ ] **HID tap under the sandbox**: `make probe-hid`. The menu must show “Active” if the HID tap is accepted under the sandbox. Compare the event count with `make probe`.
- [ ] **Launch at Login**: check the option, log out, then log back in. Thock is in the menu bar. If the menu says to allow it, turn it on in System Settings > General > Login Items.
- [ ] **Persistence**: change the volume, pack, output, spatialization, mouse sounds, rules and exclusion list. Quit, relaunch: everything is kept.

## 6. Packs

- [ ] **Import with the button**: Settings > Packs > “Import Folder…”, choose a valid folder (`pack.json` and `alpha_down_1.wav`, for example). The pack appears as “imported” after the bundled packs, it is selected and it makes sound.
- [ ] **Import by drag and drop**: drag a pack folder from the Finder onto the list. Same result.
- [ ] **Invalid pack**: drag a folder without `pack.json`, then a folder without `alpha_down`. A clear error message, nothing is added.
- [ ] **Deletion**: delete the selected imported pack. It disappears from the list and the menu, and Thock goes back to Holy Panda.

## 7. Not testable by hand

- Re-enabling on `tapDisabledByTimeout`: the code re-enables the tap and clears the held keys, and the watchdog also covers the case. There is no simple way to trigger it.
