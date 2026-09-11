<div align="center">

<img src="assets/logo.png" width="140" alt="Nami App Icon" />

# Nami

### Native macOS anime streaming with automatic source selection and high-quality playback

An anime-first streaming app that turns a stack of addons, debrid services, and release files into one clean Play button.

</div>


---

## Overview

Nami is a native macOS streaming client built around AniList metadata, a safe modular addon system, and Real-Debrid.

It discovers anime, resolves episodes across addons, parses and deduplicates release candidates, ranks every source with a transparent scoring engine, and plays the best release through an embedded libmpv engine — while keeping manual source selection one click away.

Built for:

- Anime fans who want one clean library
- Stremio-compatible addon users
- Real-Debrid subscribers
- MKV / ASS subtitle releases
- Apple Silicon Macs

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

- AniList metadata
- Trending and seasonal
- Search with history
- Anime details and episode lists
- Continue Watching shelf
- AniList account sync

</td>

<td>

- Stremio-compatible addons
- Generic HTTP addon protocol
- Release name parsing
- Episode matching
- Stream deduplication
- Real-Debrid cache probe
- Weighted scoring engine
- "Why this stream?" breakdown
- Manual source picker

</td>

<td>

- libmpv + AVPlayer engines
- Embedded ASS/SSA subtitles
- Multiple audio tracks
- Skip intro/outro (AniSkip)
- Next-episode autoplay
- Prefetch of next episode
- Resume playback progress
- Hardware decoding
- Speed and volume controls

</td>
</tr>
</table>

> **Minimum target:** macOS 15.0+ (Apple Silicon recommended)

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
xcodebuild -project Nami.xcodeproj -scheme Nami -destination platform=macOS test
```
