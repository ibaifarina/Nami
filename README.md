<div align="center">

<img src="assets/logo.png" width="140" alt="Nami App Icon" />



# Nami

### Native macOS anime streaming with automatic source selection and high-quality playback

An anime-first streaming app that turns a stack of addons, debrid services, and release files into one clean Play button.

<img width="800" height="543" alt="Demo" src="assets/main-screen-screenshot.webp" />

</div>



---

## Overview

Nami is a native macOS streaming client built around Kitsu metadata, a safe modular addon system, and Real-Debrid.

It discovers anime, resolves episodes across addons, parses and deduplicates release candidates, ranks every source with a transparent scoring engine, and plays the best release through an embedded libmpv engine — while keeping manual source selection one click away.

Built for:

* Anime fans who want one clean library
* Stremio-compatible addon users
* Real-Debrid subscribers
* MKV / ASS subtitle releases
* Apple Silicon Macs

---

## Features

<table>
<tr>
<th align="left">Discovery</th>
<th align="left">Auto-Select</th>
<th align="left">Playback</th>
</tr>

<tr>
<td>

* Kitsu metadata
* Trending and seasonal
* Search with history
* Anime details and episode lists
* Continue Watching shelf
* Local library and progress

</td>

<td>

* Stremio-compatible addons
* Generic HTTP addon protocol
* Release name parsing
* Episode matching
* Stream deduplication
* Real-Debrid cache probe
* Weighted scoring engine
* "Why this stream?" breakdown
* Manual source picker

</td>

<td>

* libmpv + AVPlayer engines
* Embedded ASS/SSA subtitles
* Multiple audio tracks
* Skip intro/outro (AniSkip)
* Next-episode autoplay
* Prefetch of next episode
* Resume playback progress
* Hardware decoding
* Speed and volume controls

</td>
</tr>
</table>

> **Minimum target:** macOS 15.0+ (Apple Silicon recommended)

---

## Addon Support

Nami works with Stremio-compatible addons.

* **Torrentio** and **Comet** are supported out of the box. Nami already understands their result format and uses a built-in optimized parser, so no format analysis is needed.
* **Other Stremio-compatible stream addons** can be added when they accept IMDb, TMDB, Kitsu, MAL, or AniList IDs. Catalog-only addons that use private item IDs cannot be matched to Nami's anime library. Compatible custom addons are analyzed on-device with Apple's AI using Foundation Models and Apple Intelligence on macOS 26+.
* On Macs where Apple Intelligence isn't available, Nami automatically falls back to its built-in parser, although parsing may be less reliable.
* Results are best when an addon includes as much release information as possible in its stream text, such as resolution, codec, dynamic range, audio and subtitle languages, release group, and file size.

Nami uses this metadata to match episodes correctly and rank sources accurately.

---

## Localization

Nami ships with English and Spanish and can display several languages. Change the app language in **Settings → General → Language**; applying it restarts the app.

All strings live in `Nami/Resources/Localizable.xcstrings`. To add a language:

1. Add a case with its language code in `Nami/Core/Domain/AppLanguage.swift`.
2. Open `Localizable.xcstrings` in Xcode, add the language, and translate the entries.

In code, SwiftUI text (`Text`, `Button`, `Label`, `.help`, `.accessibilityLabel`, and friends) is localized automatically. Plain `String` values such as enum display names, error messages, and strings passed to custom components use `String(localized:)`. Plurals are declared in the string catalog.

---

## Quick Start

### Run with Xcode

`project.yml` is the source of truth. Generate the project once, then open it and press **⌘R**.

```bash
xcodegen generate
open Nami.xcodeproj
```

### Run with the helper script

```bash
./build_and_run.sh
```

### Run the tests

```bash
xcodebuild -project Nami.xcodeproj -scheme Nami -destination platform=macOS
```
