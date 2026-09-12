

![Nami App Icon](assets/logo.png)

# Nami

### Native macOS anime streaming with automatic source selection and high-quality playback

An anime-first streaming app that turns a stack of addons, debrid services, and release files into one clean Play button.



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


| Discovery | Auto-Select | Playback |
| --------- | ----------- | -------- |




- AniList metadata
- Trending and seasonal
- Search with history
- Anime details and episode lists
- Continue Watching shelf
- AniList account sync





- Stremio-compatible addons
- Generic HTTP addon protocol
- Release name parsing
- Episode matching
- Stream deduplication
- Real-Debrid cache probe
- Weighted scoring engine
- "Why this stream?" breakdown
- Manual source picker





- libmpv + AVPlayer engines
- Embedded ASS/SSA subtitles
- Multiple audio tracks
- Skip intro/outro (AniSkip)
- Next-episode autoplay
- Prefetch of next episode
- Resume playback progress
- Hardware decoding
- Speed and volume controls



> **Minimum target:** macOS 15.0+ (Apple Silicon recommended)

---



## Addon Support

Nami works with Stremio-compatible addons.

- **Torrentio** and **Comet** are supported out of the box. Nami already understands their result format and uses a built-in optimized parser, so no format analysis is needed.
- **Any other Stremio-compatible addon** can be added as well. When it is installed, Nami analyzes the addon's stream format on-device with Apple's AI (Foundation Models with Apple Intelligence on macOS 26+). On Macs where that isn't available, Nami falls back to its built-in parser automatically, although its prone to fail.
- With every addon — including Torrentio and Comet — results are best when the addon puts as much information as possible into the stream format text, such as resolution, codec, dynamic range, audio and subtitle languages, release group, and file size. Nami reads this text to match episodes and rank sources accurately.

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

