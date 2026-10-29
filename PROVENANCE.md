# Broadcast integration record

Inspected the public production website on 29 October 2026. No account, credentials, private APIs, or administrative endpoints were used.

## Sources

- Website: https://spelunkr.tv/
- Production JavaScript: https://spelunkr.tv/assets/index-HVqlsCpR.js
- Bundle SHA-256: `4b78558a65279fb9e8ecaba44d57e5afa8caf3261c4365c65910cc78c2696b1f`
- Live broadcast root: https://jbuopkuluyfjwgsrigry.supabase.co/storage/v1/object/public/broadcast/
- Website snapshot root: https://spelunkr.tv/broadcast/

The website fetches `lineup.json`, then immutable channel manifests and their referenced platform bumper data. Hidden/debug channels and channels marked coming soon are excluded from this app.

`scripts/extract-engine.js` selects the three schedule entrypoints and their lexical dependencies using an AST and scope analysis. It emits only the pure scheduler into `web/vendor/schedule-engine.js`; the website bootstrap, UI, analytics, authentication, and network clients are excluded. The extractor rejects dependencies on browser globals or fetch. Input is treated as source text, not executed during extraction. The shared adapter imports the resulting isolated scheduler at runtime; `server/vendor/schedule-engine.js` re-exports it for the Node API and native reference tests.

Supported engine version: **5**. The extracted functions are `buildPlaylist`, `hydrateVersion`, and `resolveAt`. Their original minified names are recorded in the extraction script. A changed bundle requires reviewing/updating those entrypoints and rerunning parity checks; the extractor is deliberately not an automatic update service.

The REA static analysis reference is `ev_d56bb588851b3e5242db8666873e7081f03855cf35a941308caf7213abe10c6b`. Its semantic analysis was capped at 1,000 nodes for the production bundle and reported partial coverage. It establishes static source observations, not runtime equivalence or complete coverage of the website.

## Observed runtime reference

Playwright evaluated the website's already-loaded production module for **Computer Chronicles** at Unix time **1793280273143 ms**. The website returned:

```json
{
  "key": "12:1:256",
  "id": "CyberPri98",
  "offset": 1710,
  "startMs": 1793278563020,
  "endMs": 1793280324020
}
```

The JavaScript service and the native BrightScript scheduler both return the identical result at that timestamp using the same manifest and platform data. `tests/fixtures/website-schedule.json` preserves that input and reference result; `tests/broadcast.test.js` and `tests/native.test.js` verify it without network access. This is a specific parity check, not a claim that every website path or every device has been tested.

The finished adapter loaded all **31 public channels** with no channel errors in a live guide check. Browser validation also observed an Archive MP4 playing.

## Physical Roku validation

On 29 October 2026, the app was installed through the developer installer on the user's TCL 55S421 Roku TV (C109X), running Roku OS 16.0.4. The installer reported success and ECP identified Spelunkr as the active app. The Roku debug console reported `VODStartComplete`, and a device screenshot showed the guide with multiple correctly positioned programs, a selected program, a playing Internet Archive preview, the classic color palette, and the project credit. The final screenshot is `output/research/roku-device-guide.jpg`; the playback log is `output/research/roku-runtime-verified.log`.

On-device validation exposed two BrightScript compatibility issues, both fixed in the deployed ZIP: Integer values do not provide `ToDouble()`, so the millisecond clock now uses an explicit Double literal; JSON LongInteger timestamps need promotion to Double before division to preserve fractional program-grid positions. This validation covers startup and observed playback on this device, rather than every Archive encode or long-running playback.

## Standalone native integration

The current package, version 0.2.0, connects directly to the public live broadcast root and the website snapshot. It does not contain an adapter URL or contact a computer on the LAN. `roku/source/schedule.brs` is an independently written BrightScript port of the pinned engine 5 reference above. Unsigned arithmetic uses exact Double operations and 16-bit multiplication halves; UTF-8 strings are decoded into UTF-16 units for matching JavaScript hashes and slide timings. Channel manifests, ad plans, bumper decks, and computed cycles persist in a Task between guide refreshes and channel changes.

The native parity tests execute the shipped BrightScript source with `@rokucommunity/brs`. They compare the unsigned PRNG, Unicode hashes, the observed production playback position, both sides of the epoch, bumper transitions, synthetic seasonal and dated bumpers, ad rotation, marathon stings, cross-cycle carry, cache eviction, and version cutovers with the extracted website scheduler. The full suite has 20 passing tests, including a browser fetch-receiver regression check added for the shared client. `scripts/verify-native-live.js` provides a separate, optional check against every public live channel and saves reproducible inputs and a report under `output/research/`.

The live comparison on 29 October 2026 passed for **all 31 public channels at 341 positions**, including current playback, the next program boundaries, two hours ahead, and three days ahead across the Halloween seasonal window. It compares entry identity, exact start/end milliseconds and offset, selected ads and bumpers, and available bumper audio metadata. Inputs are preserved in `output/research/native-parity-input.json`; results are in `output/research/native-parity-report.json`. These sampled checks support schedule equivalence without claiming coverage of every possible timestamp.

The standalone ZIP was installed on the same TCL Roku TV on 29 October 2026 with the Node service stopped and port 3000 unavailable. The debug console reported a direct live lineup of 31 channels, `Direct guide ready: 31 channels, 0 errors`, `Direct tune primetime 17:1:2 video`, and `VODStartComplete`. The device screenshot shows a playing Archive preview, populated guide, matched colors, and original-project credit. Evidence: `output/research/roku-direct-runtime-verified.log` and `output/research/roku-direct-guide.jpg`. This verifies that startup, guide refresh, and observed playback work independently of the computer; it does not establish coverage of every media file or prolonged playback.

`output/research/roku-direct-verification.json` records the final package SHA-256, confirms that its MD5 matches the device installer's installed package, and records the active app version, stopped local service, populated guide, and playback evidence. The final ZIP contains the native scheduler and no LAN adapter URL or adapter API routes.

## Android and Linux clients

The Android APK and Linux Flatpak, version 0.2.0, bundle the independent HTML/CSS interface, shared direct-feed adapter, and the same pinned original scheduler. A persistent Web Worker computes guide entries and live seek positions within the installed app. Neither package includes a LAN server address. Android loads assets through AndroidX WebViewAssetLoader; Linux uses a loopback-only static asset server within its own GTK/WebKit process. All broadcast and media requests go directly to public HTTPS hosts. The footer credits Spelunkr.tv and the Internet Archive on phone, tablet, TV, and desktop layouts.

On 29 October 2026, the signed Android release compiled and passed lint with zero errors. Android build-tools verified its APK v2 release signature. Its manifest includes phone and Leanback launchers, a TV banner, an optional touchscreen, minimum API 26, and target API 35. Chromium tests against a plain static file server loaded 31 channels with no channel errors, played Archive video, and exercised touch and keyboard navigation, watch/guide switching, help, suspend, and resume. Phone (390×844), tablet (1024×768), and TV (960×540) screenshots are in `output/playwright/android-*.png`. These are shared-interface checks, not Android hardware validation: no physical Android device was connected, and the software emulator did not boot on this machine without virtualization.

The Linux bundle targets `org.gnome.Platform/x86_64/51`. Flatpak successfully built and installed it in an isolated Ubuntu WSL1 environment, and AppStream validated its application metadata. The actual GTK4 / WebKit 6.0 wrapper loaded all 31 live channels with zero channel errors, played Archive media, preserved playback while browsing, tuned the selected channel, opened and closed help, and paused/resumed media. Evidence is in `output/linux/verification.json` and `output/linux/guide.png`; the repeatable harness is `scripts/smoke-linux.py`. Xvfb, software rendering, a null audio backend, and a test-only WebKit sandbox override were required in WSL1. This environment does not support Flatpak's namespace sandbox; the smoke check ran the wrapper outside it. It does not establish physical Linux display/audio or sandboxed runtime validation. Production launchers retain normal WebKit sandbox behavior.

## Local assets

The client palette matches the production site's classic theme from `https://spelunkr.tv/assets/index-BPW2Ss7Z.css`: purple `#1C0A57`, panel blue `#21285A`, guide blue `#001040` / `#102080`, border blue `#2652B2`, yellow `#FFFF00`, and cyan `#8FFDFA`. Orange and sunset gradients use that stylesheet's color stops. `web/theme.css` records the browser theme; `scripts/make-assets.py` generates matching native gradients. Credits identify Spelunkr.tv as the original project and the Internet Archive as the video source.

Roku icon and splash PNGs were generated with `scripts/make-assets.py`. The interface is implemented independently in HTML/CSS and BrightScript/SceneGraph. JetBrains Mono is distributed under its included `OFL.txt` from https://github.com/JetBrains/JetBrainsMono.
