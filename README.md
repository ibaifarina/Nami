<div align="center">

<img src="assets/logo.png" width="140" alt="Nami App Icon" />

# Nami

### A native macOS anime player where Play just works.

Nami automatically finds, ranks, validates, and plays the best available source —  
so you don't have to choose between a list of releases every time you want to watch something.

<br>

<img width="800" alt="Nami Home" src="assets/main-screen-screenshot.webp" />

</div>

---

## Overview

Nami is a native macOS anime streaming client focused on making anime playback feel effortless.

Instead of presenting a long list of sources and asking you to figure out which one works, Nami handles the process automatically:

**Find → Match → Rank → Validate → Play**

Under the hood, Nami combines Kitsu metadata, Stremio-compatible addons, Real-Debrid, automatic release parsing, and an embedded `libmpv` player.

If the preferred source fails, Nami can automatically move on to the next best candidate. Manual source selection is always available when you want it.

The interface is available in:

- 🇬🇧 English
- 🇪🇸 Spanish

### Built for

- Anime-first discovery and browsing
- One-click playback
- Stremio-compatible stream addons
- Real-Debrid
- High-quality MKV releases
- ASS / SSA subtitles
- Apple Silicon Macs

---

## Features

<table>
<tr>
<th align="left">Discover</th>
<th align="left">Smart Sources</th>
<th align="left">Watch</th>
</tr>

<tr>
<td valign="top">

- Kitsu metadata
- Trending & seasonal anime
- Search with history
- Anime details
- Seasons & episodes
- Continue Watching
- Local watch progress
- English & Spanish UI

</td>

<td valign="top">

- Stremio-compatible addons
- Torrentio, Comet & AIOStreams support
- Automatic episode matching
- Release metadata parsing
- Stream deduplication
- Real-Debrid cache detection
- Automatic source ranking
- Stream validation & fallback
- "Why this stream?" scoring
- Manual source picker

</td>

<td valign="top">

- `libmpv` playback
- MKV support
- ASS / SSA subtitles
- Multiple audio tracks
- AniSkip intro / outro skipping
- Next-episode autoplay
- Next-episode prefetching
- Resume playback
- Hardware decoding
- Playback speed & volume controls

</td>
</tr>
</table>

> **Requires macOS 15.0+**  
> Apple Silicon is recommended.

---

## Automatic Source Selection

Nami is designed around automatic playback rather than manual source selection.

When you press **Play**, Nami evaluates available releases using signals such as:

- Episode match confidence
- Real-Debrid cache availability
- Resolution
- Release source
- Video codec
- File size / bitrate
- Audio and subtitle languages
- Release group
- Seeder availability
- Addon priority

Candidates are ranked using a transparent scoring engine and the strongest sources are validated before playback.

If a source is unavailable, blocked, or invalid, Nami can automatically try the next preferred candidate.

You can still open the source picker at any time and choose manually.

---

## Addon Support

Nami supports **Stremio-compatible stream addons**.

### Optimized addons

Nami includes optimized support for:

- **Torrentio**
- **Comet**

Nami understands their stream result formats directly and can extract release metadata without additional format analysis.

> These addons are not bundled or installed automatically. Nami only provides compatibility with addons configured by the user.

### AIOStreams

**AIOStreams is also supported.**

Because AIOStreams allows users to customize the formatting of stream results, Nami cannot assume one fixed output format.

When configuring AIOStreams for Nami, it is strongly recommended to include as much release information as possible in the displayed stream text.

Useful information includes:

- Resolution — `1080p`, `2160p`, etc.
- Codec — `H264`, `HEVC`, `AV1`
- Dynamic range — `HDR`, `HDR10`, `Dolby Vision`
- Audio language
- Subtitle language
- Dual Audio indicators
- Release group
- File size
- Seeder count
- Debrid/cache status
- Release/source name

The more information the addon exposes, the more accurately Nami can understand, compare, and rank its results.

For example, this is much more useful to Nami:

```text
1080p · HEVC · Japanese · English Subs
SubsPlease · 1.2 GB · RD+
