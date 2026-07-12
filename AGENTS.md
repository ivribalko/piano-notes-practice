# Agents

Minimal native SwiftUI iOS app with no packages or network dependencies. See `ARCHITECTURE.md` for structure and component ownership.

- This repository is public. Never commit secrets, private identifiers, signing configuration, credentials, or other sensitive data.
- The dark app icon must use a transparent outer background and transparent symbol cutouts; do not add a background gradient.
- Whenever the app icon changes, update `docs/assets/app-icon.svg` from the canonical Icon Composer artwork in `PianoNotesPractice/AppIcon.icon/Assets` so the website uses the same design.

## Product Behavior

- Show one Staff Cue, play enabled sounds, advance after correct answers, and keep the Cue after misses.
- Generate selected Clefs across Octaves `2...6`; Octave 4 starts enabled. Answers are `C` through `B`.
- Follow native light and dark backgrounds while keeping Staff, notation, note paper, and piano surfaces light with black content.
- Reuse shared design values such as `Theme.selectedControlTint` for active states.
- Capitalize music feature terms in user-facing text: Practice, Clef, Octave, Sharps and Flats, White Keys, Black Keys, Staff, and Cue.
- Never use “accidentals” in user-facing text; use “Sharps and Flats.”
- End Tutorial and helper text with a period and celebration text with an exclamation mark.
- Preserve landscape on devices connected to USB MIDI keyboards.
- Confirm destructive actions with “Are you sure?”.
- Prefer ease-out cubic timing over linear animation.
- Let active audio finish naturally. New sounds may cancel pending notes but must not stop active prompt, keyboard, or celebration playback abruptly.

## Store Capture Baseline

- Use the iPhone 17 Pro Max Simulator and native 1320-by-2868 portrait output.
- Use Release through the scheme’s Profile action; never use Debug.
- Standardize the status bar to `9:41`, 100% battery, full Wi-Fi, and full cellular signal.
- Before each capture session, stop active recorders, uninstall the Simulator app, install the current build, and launch once. Reinstalling without uninstalling is insufficient.
- Keep raw captures and final deliverables under `StoreAssets`.
- The user performs final visual and synchronization verification.

## Store Video

- Compile with `STORE_TUTORIAL_CAPTURE`, record in Light Mode, disable Cue Sounds, and keep keyboard effects enabled.
- Do not terminate or relaunch after the clean launch. The app begins on the static Welcome screen and waits 10 seconds before animation and automation.
- Start recording after the same 10-second wait. Keep every prompt visible for its configured delay; helper text begins a prompt’s full delay before the next action. Never show Octave overviews during a Tutorial.
- Capture Simulator audio concurrently through ScreenCaptureKit because `simctl io recordVideo` is silent. Use stereo 256 kbps AAC at 48 kHz and align streams from capture timestamps; never reuse audio, guess offsets, or remove required ending audio.
- Deliver H.264 video with stereo AAC, 15–30 seconds long, at no more than 30 fps.
- Save the final movie as `StoreAssets/Piano-Notes-Practice-Store-Preview.mov`; remove raw temporary recordings after successful muxing.
- Validate duration, codecs, sample rate, channels, and audible signal.

## Store Screenshots

- Capture `01`–`03` and `05`–`07` in Light Mode and `04` in Dark Mode. Do not use Store video compilation defines or automation.
- Capture the required 13-inch iPad screenshot in Light Mode from a clean Release install on the iPad Pro 13-inch Simulator, with the status bar standardized to `9:41`, 100% battery, full Wi-Fi, and full cellular signal.
- Use a clean install for each state-specific Practice capture so progress and settings never leak between states.
- `01-Practice-Highlighted-C.png`: complete Welcome, Piano Keyboard, and Sheet Music Staff Tutorial introductions; dismiss the highlighted White Piano Key overlay without answering; show the full keyboard with C highlighted.
- `02-Practice-Cue-Sounds.png`: regular Practice, Cue Sounds on, Cue Staff off, and On-Screen Piano Keyboard below `Tap to replay`.
- `03-Practice-MIDI.png`: regular Practice, Cue Staff on, one Staff Note, and the MIDI answer panel.
- `04-Practice-Dark-Mode.png`: system Dark Mode, Cue Staff on, On-Screen Piano Keyboard visible, and Darker Practice Mode off.
- `05-Progress.png`: untouched Progress root.
- `06-Settings-Practice-Display.png` and `07-Settings-Practice-Cue.png`: matching Settings detail screens with defaults.
- Remove obsolete captures, then save exactly those seven PNGs under `StoreAssets/Screenshots/6.9-inch` and verify each is 1320 by 2868.
- Save the native iPad capture as `StoreAssets/Screenshots/13-inch/01-Practice.png` and verify it is 2064 by 2752.

## Store Composition

- Treat raw captures as immutable. Never stretch images; crop or extend the canvas while preserving aspect ratio.
- Keep the approved continuous 13200-by-2868 panorama at `StoreAssets/Backgrounds/aurora-party-balloons-panorama.png` and generated slices under `Backgrounds/6.9-inch`.
- The panorama must remain one seamless blurred blue-purple aurora source with naturally varied balloons and quiet headline/card areas. Never stitch, mirror, duplicate, or distort balloon artwork.
- Save regenerated panorama candidates under versioned names and obtain explicit approval before replacing the canonical panorama, slices, or final screenshots.
- Use `StoreAssets/Scripts/compose_store_screenshots.swift`, never image generation, to combine backgrounds, captures, and headings. The script owns headline copy and screenshot pairing.
- Use the compositor's `--ipad` option to create `StoreAssets/01-Practice-13-inch-iPad.png` with the headline “Practice by Playing on iPad.” Preserve the native iPad capture without stretching and use the approved panorama as one continuous cropped source.
- Generate slices, then compose from the repository root:

```bash
./StoreAssets/Scripts/slice_store_background.swift
```

```bash
./StoreAssets/Scripts/compose_store_screenshots.swift
```

```bash
./StoreAssets/Scripts/compose_store_screenshots.swift --ipad
```

- Final PNGs sit in `StoreAssets` beside the preview movie. The compositor may replace only its seven outputs.
- Verify exactly seven 1320-by-2868 RGB PNGs without alpha, correct headlines and panorama segments, and complete unclipped cards.
- Verify the composed iPad PNG is 2064 by 2752, RGB without alpha, with the correct headline and a complete unclipped card.

## Build Verification

- For App Store builds, bump the minor version unless the user specifies otherwise, always use build number `1`, upload the build to App Store Connect, then create and push a tag for that version to the remote repository.
- Use direct `xcodebuild`, `xcrun simctl`, and Apple command-line tools; never use XcodeBuildMCP.
- After source changes, rebuild, reinstall, and launch in the Apple Simulator app.
- Never use a Simulator mirror, `serve-sim`, or the in-app browser for Simulator verification.
- Do not inspect the launched app; the user verifies it. Skip build/device verification for docs, metadata, instructions, and Store asset or composition-only changes.
- Use physical devices only when explicitly requested. Never uninstall a physical-device app without explicit permission.
- When a device name is supplied, list devices and select the closest available match instead of assuming the default.
- Keep `IOS_DEVICE_ID`, `DEVELOPMENT_TEAM`, and the bundle identifier in ignored `secrets/Signing.xcconfig`. Prefer quiet builds and inspect verbose output only after failure.

Physical-device workflow:

```bash
source secrets/Signing.xcconfig
xcodebuild -quiet -project PianoNotesPractice.xcodeproj -scheme PianoNotesPractice -configuration Debug -destination "id=$IOS_DEVICE_ID" -derivedDataPath DerivedData build
xcrun devicectl device install app --device "$IOS_DEVICE_ID" "DerivedData/Build/Products/Debug-iphoneos/Piano Notes Practice.app"
xcrun devicectl device process launch --device "$IOS_DEVICE_ID"
```

- For a one-off non-default device, replace `IOS_DEVICE_ID` inline without storing it.
- On signing failure, verify `DEVELOPMENT_TEAM`, let Xcode load project signing once, and retry.
