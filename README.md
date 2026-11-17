# PatsHelloworld Soundboard

Play sounds through your Mac from a phone or browser on the same Wi‑Fi. The Mac app comes with 15 starter effects and can also switch OBS scenes, mute or unmute the mic, and start or stop recording.

## Install on macOS

1. Download `PatsHelloworld-Soundboard-macOS.zip` from the [latest release](https://github.com/patshelloworld/PatsHelloworld-Soundboard/releases/latest).
2. Unzip it and drag **PatsHelloworld-Soundboard.app** into **Applications**. The download contains a universal build for Apple silicon and Intel Macs running macOS 13 or later.
3. Open the app. This release is ad hoc signed. If macOS blocks the first launch, you can build locally using the steps below. If you trust the download, Apple also documents how to open it through **System Settings → Privacy & Security → Open Anyway**. [Apple’s Gatekeeper guide](https://support.apple.com/en-us/102445)

## Pair your phone or browser

Keep the app open and connect both devices to the same Wi‑Fi. Grant local network access if macOS prompts. Scan the QR code with the iPhone camera or use **Copy Link** to open the board in a browser on another device. Tap a pad to play through the Mac's selected audio output. In Safari on iPhone, use **Share → Add to Home Screen** to save the board.

Keep the pairing link and QR code private. They let people on your network trigger audio and configured OBS actions. The app serves the controller from your Mac over your local network.

## Customize sounds

- Select a pad in the Mac app and click **Customize**. Choose an audio file, edit the label and icon, or set the volume. **Preview** plays it on the Mac. **Restore Default** restores the original sound and settings for that pad.
- To load a collection at once, put a folder named `sounds` next to the `.app` and relaunch. The folder accepts MP3, WAV, M4A, AAC, AIF, AIFF, CAF, and FLAC. The app adds pads when the folder contains more than 15 compatible files. Saved customizations take precedence on their pads.

## OBS setup

**Capture soundboard audio.** In OBS Studio 30 or later, add a **macOS Audio Capture** source and select **PatsHelloworld Soundboard**. Make a short test recording to verify the level. If your OBS setup already captures all desktop audio, check that the sound enters the mix only once. [OBS macOS audio capture guide](https://obsproject.com/kb/macos-desktop-audio-capture-guide)

**Control OBS.** In OBS Studio 28 or later, open **Tools → WebSocket Server Settings**, enable the server, and leave password authentication on. Open **OBS Settings** in the Mac app and enter the port and password. Enter your exact Audio Mixer input name if you use a custom microphone. On the paired device, tap **OBS** to switch scenes, toggle the mic, or start and stop recording. [OBS remote control guide](https://obsproject.com/kb/remote-control-guide)

## Troubleshooting

- **Phone can't connect.** Click **Open on Mac** to verify the server locally. Check that both devices are on the same network and that the Mac app has local network permission. Guest Wi‑Fi may block connections between devices. If the `.local` hostname fails to resolve, replace just the hostname in the pairing link with the Mac's local Wi‑Fi IP address.
- **Pad plays silently.** Check the Mac's selected sound output and the pad volume in **Customize**. Use **Preview** to check an imported file.
- **OBS actions are unavailable.** Keep OBS running on the same Mac and check the WebSocket port and password in **OBS Settings**.

## Build from source

You'll need macOS 13 or later, Apple’s Xcode Command Line Tools (`xcode-select --install`), and Python 3.

```bash
bash Source/build.sh
open Source/build/PatsHelloworld-Soundboard.app
```

Use `bash Source/build.sh --universal` to build for both Apple silicon and Intel. Run the audio self-check with this command.

```bash
Source/build/PatsHelloworld-Soundboard.app/Contents/MacOS/Soundboard --check-audio
```
