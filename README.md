# Spelunkr Guide for Roku, Android, and Linux

A classic cable guide for the real channels at [spelunkr.tv](https://spelunkr.tv), available as a native BrightScript / SceneGraph Roku app, an Android APK for phones, tablets, and Android TV, and a Linux Flatpak. A browser version is included.

The interface uses Spelunkr's classic purple, blue, yellow, cyan, and orange palette. The browser footer links to **Original project by Spelunkr.tv**; the Roku guide, help screen, and splash screen also credit the original project. Video attribution to the Internet Archive appears alongside it.

All three installed apps connect directly to Spelunkr's public broadcast data and play video directly from the Internet Archive. **Your computer can be turned off.** The current public lineup has 31 channels; names, numbers, programs, and schedule updates come from Spelunkr.

## Downloads

Installers are available on the public [GitHub Releases page](https://github.com/buddytohelpu/spelunkr-guide/releases/latest):

| Platform | Download |
| --- | --- |
| Linux x86_64 | [Flatpak bundle](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-guide-x86_64.flatpak) |
| Android phones, tablets, and TV | [Signed APK](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-guide-android.apk) |
| Roku | [Developer ZIP](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-roku.zip) |

This is an independent client for the original [Spelunkr.tv](https://spelunkr.tv/) project. Broadcast data, the pinned upstream scheduler, and bundled fonts retain their attribution in [PROVENANCE.md](PROVENANCE.md) and the included font license. GitHub hosts the source and installers; the apps fetch broadcasts directly from their public sources.

## Android phones, tablets, and Android TV

Install **[spelunkr-guide-android.apk](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-guide-android.apk)** on Android 8.0 or later with a current Android System WebView. Open the APK on the device and allow installation from that source when Android prompts. The same signed APK includes both the regular app launcher and the Android TV launcher with a television banner.

Phones and tablets use a compact guide with a playing preview and touch controls. The channel list scrolls within the available screen height, including in landscape. Tap a program to select it, then tap **Watch channel**, or tap the selected program again. Android TV automatically uses a layout sized for television and accepts D-pad, OK, Back, channel, and Menu / Info keys. Watch fills the screen and hides Android's system bars; **Guide** or Android Back returns to the guide and restores the bars on phones and tablets. Back from the guide exits. The player pauses when the app leaves the foreground and rejoins the live broadcast on return.

You can also install over an already authorized ADB connection:

```sh
adb install -r spelunkr-guide-android.apk
```

The app bundles its interface and scheduler. It fetches the public feeds and Archive media itself; it needs no computer address or companion service.

To rebuild on Windows, install JDK 17 and Android SDK Platform / Build Tools 35, then run:

```powershell
.\scripts\package-android.ps1
```

The script builds and lints a signed release APK. It creates or reuses a local release key in `.local/android-signing/`. Keep that directory private and backed up: future updates must use the same signing key. An optional `-GradleCommand` argument selects an existing Gradle 8.11.1 installation. The checked-in Gradle wrapper also uses 8.11.1 and verifies its distribution checksum.

## Linux Flatpak

Install **[spelunkr-guide-x86_64.flatpak](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-guide-x86_64.flatpak)** on a Linux desktop with Flatpak. Download and open the bundle in your software installer, or use the terminal:

```sh
curl -fL -o spelunkr-guide-x86_64.flatpak https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-guide-x86_64.flatpak
flatpak install --user ./spelunkr-guide-x86_64.flatpak
flatpak run io.github.buddy.SpelunkrGuide
```

Flatpak can download the required GNOME 51 runtime from Flathub when prompted. After installation, **Spelunkr Guide** also appears in your application launcher. This build is for x86_64 computers.

New app versions are distributed as GitHub release bundles; install the latest bundle again to update the app. Flatpak handles runtime updates through Flathub. This project is currently distributed through GitHub Releases.

Use the arrow keys and Enter to browse and watch, Escape to return to the guide, F11 to toggle full screen, and Ctrl+Q to quit. The GTK4 / WebKit client bundles the interface and scheduler. Its own process serves bundled assets on a loopback-only port; schedules and video come directly from the internet. It needs no separately running server.

To rebuild on Linux, install Python 3, Flatpak, and an SVG icon loader (on Ubuntu, `librsvg2-common`), then run:

```sh
python3 scripts/package-flatpak.py
```

The packager exports the bundled Python client and web assets without downloading a compiler SDK. To run from source, install PyGObject, GTK4, WebKitGTK 6.0, and suitable GStreamer codecs, then run `python3 clients/linux/main.py`.

## Screen sizes and picture proportions

Android, Linux, and the browser fit the guide to the current window, with scrolling inside the channel list. The layout adapts to portrait, landscape, small desktop windows, and television screens. TV controls and credits include a margin for overscan. The Linux window starts within the monitor's available dimensions and can resize down to 480×320; the phone layout also supports 320×480 portrait screens. The native Roku guide scales its HD design to the device's display.

The **Original / Stretch** button above the preview and fullscreen picture changes video fitting in Android, Linux, and the browser. **Original** preserves the video's proportions. **Stretch** fills the frame and may widen older 4:3 footage; black bars already encoded into a file remain part of the picture. The app remembers your choice. Keyboard users can press **S**. On Android TV, open **Remote help** with Menu / Info, then press Left / Right to change picture mode. The fullscreen **Guide** button returns touch users to the guide. Linux users can press **F11** to fill the entire desktop display.

Version 0.3.0 also fixes Linux playback that continued with audio after selecting Watch: WebKit could give the fixed video container zero height. Fullscreen video now has explicit dimensions, and the Linux smoke check verifies that its visible rectangle matches the window.

## Optional browser preview

Requires Node.js 20.12 or later.

```powershell
npm install
npm start
```

Open **http://localhost:3000**. The browser guide also works on another device using your computer's LAN address, printed when the server starts.

| Remote | Browser | Action |
| --- | --- | --- |
| Up / Down | Arrow keys | Browse the guide; change channels when watching |
| Left / Right | Arrow keys | Select programs in the schedule |
| OK | Enter | Watch the selected channel; open the guide when watching |
| Back | Escape | Return to the guide; on Roku, Back from the guide exits |
| Star | ? or * | Remote help |
| TV volume controls | M | Sound / mute |

Browsing leaves your current channel playing in the preview. Selecting a future program tunes to that channel's **live** broadcast. The app remembers your last channel. The browser starts muted because browsers restrict autoplay with sound; click **Sound off** to enable audio.

## Load onto your Roku

The prepared standalone package is **[spelunkr-roku.zip](https://github.com/buddytohelpu/spelunkr-guide/releases/latest/download/spelunkr-roku.zip)**. The Roku only needs an internet connection. No server, LAN address, or configuration file is needed.

1. On the Roku remote, enter **Home ×3, Up ×2, Right, Left, Right, Left, Right** to open developer settings. Enable the developer installer, choose a password, and let the Roku restart.
2. Visit `http://YOUR_ROKU_IP` from your computer. Sign in as `rokudev` with the password you chose.
3. Upload the downloaded `spelunkr-roku.zip` and select **Install**. The app opens on the Roku. Your computer is only needed to install or update it.

To rebuild from source after installing npm dependencies:

```powershell
npm run build:roku
```

Sideloading uses Roku's development slot. The standalone build was installed on a **TCL 55S421 Roku TV running Roku OS 16.0.4** on 29 October 2026. All 31 guide rows and Internet Archive playback were verified with the computer's server stopped. It has not been published to the Roku Store.

## Direct broadcast connection

Spelunkr publishes versioned playlists, rather than a single live HLS stream. Its browser computes the current video using a deterministic scheduler that includes station breaks, vintage ads, seasonal bumpers, program cut points, and scheduled lineup changes. Counting video durations alone would put the Roku behind the website.

`roku/source/schedule.brs` implements that scheduler in BrightScript, including deterministic random selection, bumper decks, UTF-16 text timing, seasonal choices, marathon cards, vintage ad rotation, cycle carry, and published version cutovers. A persistent Task fetches the public HTTPS feeds, calculates the guide, and resolves the live seek position on the Roku. The interface remains responsive while it loads, prioritizes the last channel, and fills the other guide rows in the background.

The lineup refreshes every minute. Immutable manifests and computed cycles are cached in memory. During an outage, an existing live lineup takes priority over the website's older snapshot. On a fresh startup, the website snapshot is a fallback when live storage is unavailable. See [PROVENANCE.md](PROVENANCE.md) for sources and verification.

Android, Linux, and the browser run the pinned JavaScript scheduler in a Web Worker. The same direct broadcast adapter handles their guide and tuning requests. The optional Node service serves the browser files and retains the original adapter API for compatibility and tests; the browser no longer calls that API. Any static HTTP server can serve `web/`, and the Dockerfile can host it. None of the installed apps uses a computer's Node service.

## Checks

```powershell
npm test
npm run check:roku
npm run build:roku
```

The 20 tests cover the observed website playback position, browser-native fetch binding, native PRNG and Unicode behavior, bumper and ad boundaries, seasonal decks, marathon cards, cycle carry, cache eviction, version changes, seek offsets, schedule fallback, navigation, and HTTP validation. Native tests execute the actual BrightScript scheduler with the RokuCommunity interpreter and compare its results with the pinned website scheduler. The Roku package is checked with the BrightScript compiler and on the physical Roku.

The Android release passes compilation, lint (zero errors), and APK signature validation. Manifest inspection confirms Android 8+, both launcher types, and an optional touchscreen. Two Android 15 / API 35 emulator tests in GitHub Actions verify the real WebView and native fullscreen bridge, system bars, Back to the guide, portrait/landscape rotation, video bounds, and the saved picture setting after Activity recreation. These tests do not require a network connection. Chromium checks additionally cover phone touch controls, tablet and TV layouts, all 31 live channels, Archive playback, help, Back, and pause/resume. Physical Android hardware and live video playback on Android remain unverified.

The Flatpak bundle was built, installed, and its metadata validated in an isolated WSL1 build environment. The actual GTK/WebKit wrapper passed live guide, visible fullscreen Archive playback, Original / Stretch, navigation, help, and pause/resume checks under Xvfb, including a 736×416 window. The picture choice also survived a full app restart. `scripts/smoke-linux.py` records results in `output/linux/verification.json` and checks that fullscreen video fills the window. WSL1 cannot run Flatpak's namespace sandbox, so this was a source-wrapper test rather than a sandboxed desktop launch. Test-only WebKit sandbox and software/audio settings were used for that environment; the installed launcher does not disable its sandbox. A physical Linux desktop and audio output remain untested.

An optional live integration check compares every current public channel at program boundaries and future timestamps:

```powershell
node scripts/verify-native-live.js
```

It writes its input and report to `output/research/native-parity-*.json`. The 29 October 2026 live check passed for all 31 channels at 341 sampled positions. Device screenshots and debug logs are in `output/research/`; browser screenshots are in `output/playwright/`.

## Project layout

- `roku/` — standalone Roku app, native schedule engine, direct HTTPS worker, remote controls, fonts, and artwork.
- `clients/android/` — Android phone, tablet, and television wrapper, resources, and Gradle build.
- `clients/linux/` — GTK4 / WebKit desktop client and Flatpak metadata.
- `server/` — optional static server and compatible schedule API.
- `web/` — shared direct broadcast adapter, pinned scheduler, worker, guide, and controls.
- `scripts/` — package builders, Linux smoke check, schedule extractor, and artwork generator.
- `tests/` — schedule, navigation, and HTTP checks.
- `dist/` — built Roku ZIP, signed Android APK, and Linux Flatpak.

## Current limits

- Video synchronization is exact at the schedule level. Playback seeks to live after loading and periodically corrects drift; network and decoder buffering can cause a few seconds of difference between devices.
- Roku's actual media support depends on the device and each Archive encode. Playback failures retry without advancing the broadcast clock. Startup, guide rendering, and video playback have been verified on one TCL Roku TV; broader codec coverage and long-running playback still need testing.
- On Roku, station breaks use a simple native text treatment. Their time slots and vintage ad clips follow the site's schedule. The website's separate music overlay on **Vacation Slides** is not reproduced in this version.
- If Spelunkr publishes a newer scheduler engine, the app reports that an update is required instead of guessing at the timeline.

Fonts are JetBrains Mono under the SIL Open Font License; the license ships with every client. Spelunkr's broadcast data and scheduler retain their upstream provenance.
