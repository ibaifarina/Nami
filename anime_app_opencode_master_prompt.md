# Master Build Prompt — Premium macOS Anime Streaming App

# SKILLS

Before implementing anything, inspect the agent skills currently available in
OpenCode.

If `/find-skills` is available, use it to search for high-quality skills relevant
to this project, especially:

- Swift
- SwiftUI
- macOS application development
- Xcode build/test/debug workflows
- Swift concurrency
- macOS Keychain/security
- native macOS UI/UX
- video/media playback
- testing

Do NOT install skills simply because they sound vaguely relevant.

Prefer:
1. official or reputable skills
2. narrowly scoped skills
3. skills with concrete technical guidance

Avoid:
- unrelated web/frontend skills
- redundant skills
- enormous generic instruction packs
- skills that conflict with this project's architecture

Before installing or relying on a newly discovered skill, briefly state:
- what the skill does
- why it is useful for this project
- whether it changes any architectural decision

Then use relevant installed skills during implementation when their scope matches
the current task.

Skills supplement this specification. They do NOT override the architecture,
security requirements, phased implementation plan, or product requirements in
this document.

You are the lead engineer, product engineer, and implementation agent for this repository.

Your job is to build a **premium native macOS anime streaming application** with:

- AniList metadata, discovery, library, and progress sync
- A safe modular addon/provider system
- Real-Debrid integration
- Automatic selection of the best stream
- Manual source selection when the user wants control
- High-quality anime playback
- A polished UI that feels closer to Netflix / Apple TV / Crunchyroll than to a torrent client or admin dashboard
- An architecture that can reasonably expand to iPadOS later

This file is both the **product specification** and the **technical implementation plan**. Follow it closely. Do not improvise a completely different architecture without a concrete technical reason.

The priority order is:

1. Correctness
2. Maintainability
3. User experience
4. Security
5. Performance
6. Feature breadth

Do not sacrifice the first five just to add more features.

---

# 1. How You Must Work

This project will be built incrementally.

Before making major changes:

1. Inspect the entire repository.
2. Read existing README/config/build files.
3. Identify the existing architecture and stack.
4. Identify what already works.
5. Explain what you intend to change.
6. Create a concise implementation checklist for the current phase.
7. Implement only that phase.
8. Build and test.
9. Fix errors.
10. Summarize exactly what is complete and what remains.

Do **not** implement the entire application in one giant pass.

Do **not** create 50 files of speculative architecture before there is working product code.

Do **not** replace working code simply because you prefer another pattern.

Do **not** claim functionality works unless it has been verified when verification is possible.

If a feature cannot yet be implemented correctly, use a clear TODO and explain the dependency instead of pretending it works.

When uncertain, choose the simplest solution that keeps the architecture clean.

---

# 2. Product Vision

The app is a native, anime-first streaming application for macOS.

The normal user experience should be:

```text
Open app
→ Continue Watching
→ Play
→ video starts
```

or:

```text
Open app
→ Discover anime
→ Open anime
→ Choose episode
→ Play
→ video starts
```

The app may internally perform:

```text
Query addons
→ normalize results
→ identify correct episode
→ check Real-Debrid cache
→ rank candidates
→ resolve best candidate
→ prepare player
```

but this complexity should normally remain invisible.

The user should **not** feel like they are operating:

- a torrent client
- a developer console
- a media server dashboard
- an admin panel
- a database browser

The product should feel like a premium consumer streaming app.

Advanced users must still be able to inspect and manually choose sources.

---

# 3. Primary Platform and Technical Baseline

Primary platform:

- macOS
- Apple Silicon first
- M1 and newer should work well

Future target:

- iPadOS / iOS may be added later

Unless the repository already strongly justifies another stack, prefer:

- Swift 6+
- SwiftUI
- Swift Concurrency
- URLSession
- Codable
- Keychain
- SwiftData for non-sensitive local persistence
- OSLog / Logger for structured logging
- XCTest / Swift Testing depending on the project baseline

Prefer Apple frameworks before adding third-party dependencies.

Do not add a dependency simply to save 20 lines of straightforward code.

If an external library is justified, explain:

- why it is needed
- whether it is actively maintained
- how it affects distribution
- how it affects macOS/iPadOS compatibility

---

# 4. Architecture

Use clear architectural boundaries.

Recommended top-level structure:

```text
App/
    AppEntry.swift
    AppEnvironment.swift
    AppRouter.swift
    RootView.swift

Core/
    Domain/
        Anime.swift
        Episode.swift
        MediaIdentity.swift
        StreamCandidate.swift
        PlaybackProgress.swift
        InstalledAddon.swift
        UserPreferences.swift

    Networking/
        HTTPClient.swift
        HTTPError.swift
        RequestBuilder.swift

    Persistence/
        PersistenceController.swift
        Models/
        Repositories/

    Security/
        KeychainStore.swift

    Logging/
        AppLogger.swift

    Utilities/
        Timeout.swift
        StringNormalization.swift

Services/
    AniList/
        AniListClient.swift
        AniListModels.swift
        AniListRepository.swift
        AniListAuthService.swift

    Addons/
        AddonProtocol.swift
        AddonRegistry.swift
        AddonManager.swift
        AddonManifest.swift
        GenericHTTPAddonAdapter.swift
        StremioAddonAdapter.swift

    Streaming/
        StreamDiscoveryService.swift
        StreamNormalizer.swift
        StreamDeduplicator.swift
        ReleaseParser.swift
        EpisodeMatcher.swift
        StreamScoringEngine.swift
        AutoSelectService.swift

    Debrid/
        DebridService.swift
        RealDebridService.swift
        RealDebridModels.swift

    Playback/
        PlayerEngine.swift
        PlaybackCoordinator.swift
        AVPlayerEngine.swift
        MPVPlayerEngine.swift

Features/
    Home/
    Discover/
    AnimeDetails/
    Library/
    SourcePicker/
    Player/
    Settings/
        General/
        AniList/
        Streaming/
        RealDebrid/
        Addons/
        Playback/
        Advanced/

DesignSystem/
    DesignTokens.swift
    Typography.swift
    Components/
        AnimePosterCard.swift
        ContinueWatchingCard.swift
        HeroSection.swift
        LoadingSkeleton.swift
        EmptyStateView.swift
        ErrorStateView.swift
        Pill.swift
        PrimaryButton.swift

Tests/
    Streaming/
    AniList/
    Debrid/
    Persistence/
```

This is a guideline, not a command to create every file immediately.

Create files when the implementation actually needs them.

---

# 5. Dependency Direction

Keep dependency direction simple.

```text
SwiftUI Features
      ↓
Repositories / Coordinators / Services
      ↓
Domain Models
      ↓
Network / Persistence / External APIs
```

Views must not contain:

- raw URLSession requests
- Real-Debrid logic
- torrent parsing
- stream ranking algorithms
- Keychain access
- AniList GraphQL construction

Views should primarily render state and send user intents.

---

# 6. Application State

Prefer modern Swift Observation when available.

Use patterns such as:

```swift
@Observable
@MainActor
final class HomeViewModel {
    ...
}
```

or the existing repository's equivalent.

Rules:

- UI-facing mutable state should be isolated to `@MainActor`
- network and parsing work should not block the main actor
- cache/repository state may use actors when shared concurrently
- avoid global mutable singletons
- dependencies should be passed through an `AppEnvironment` or another simple dependency container

Do not build an elaborate dependency-injection framework.

---

# 7. UI Design System

The UI is a major part of the product.

It must not look like Seanime, an admin dashboard, or generic generated software.

Visual direction:

- dark-first
- native macOS feel
- premium streaming-service feel
- anime artwork is the primary visual element
- minimal chrome
- strong hierarchy
- restrained glass/material effects
- almost no unnecessary borders
- comfortable whitespace
- smooth but subtle animations
- excellent hover/focus feedback

Use system typography unless there is a strong reason not to.

Do not ship custom fonts for the MVP.

## Design tokens

Create centralized tokens rather than scattering arbitrary values.

Suggested spacing scale:

```text
4
8
12
16
20
24
32
40
48
64
```

Suggested corner radii:

```text
Small controls: 8
Buttons / chips: 10
Cards: 12–16
Large hero surfaces: 18–22
```

Suggested animation timing:

```text
Hover: 0.12–0.18s
Navigation/content transitions: 0.20–0.30s
```

Avoid dramatic spring effects everywhere.

Use them only where they feel natural.

## Window behavior

Recommended minimum window size:

```text
~1000 × 680
```

The layout must work well when resized.

Do not assume fullscreen.

## Sidebar

Use a compact native-feeling sidebar.

Items:

- Home
- Discover
- Library

Secondary access:

- Search
- Settings
- Profile

Do not put 15 navigation items in the sidebar.

## Content padding

Typical main content horizontal padding:

```text
24–32pt
```

Larger windows may use more.

## Poster ratio

Anime posters should use approximately:

```text
2:3
```

Do not stretch artwork.

Use `scaledToFill` with clipping where necessary.

## Poster cards

Poster cards should contain minimal metadata.

Typical card:

```text
[poster]

Frieren
TV · 2023
```

Do not put 8 badges on every card.

Show richer information on hover/details screens.

## Hover behavior

On macOS:

- slightly brighten or elevate the focused card
- optional tiny scale around 1.01–1.02
- reveal useful contextual controls
- do not make cards jump around

## Materials

Use native materials selectively.

Good uses:

- sidebar
- floating player controls
- overlays
- source picker background

Bad use:

- every single card having glass
- excessive translucent panels nested inside other translucent panels

---

# 8. Home Screen

Home should optimize for actually watching anime.

Order should roughly prioritize:

1. Continue Watching
2. Currently Watching
3. Trending
4. Popular This Season
5. Recommended
6. Recently Updated if reliable data is available

Do not display all sections if the user has no data.

## Continue Watching

This is the most important row.

Card should show:

- artwork
- title
- episode number
- playback progress
- optional time remaining
- Resume button on hover/focus

Example:

```text
Frieren
Episode 7
18:31 / 24:12

██████████████░░░░
```

Clicking the primary surface should resume playback.

If Auto Select is enabled, the app should resolve a source automatically.

## Hero

A hero area is optional.

If implemented:

- one featured anime
- background artwork
- readable gradient/contrast treatment
- title
- short description
- Play
- Details

Do not make the hero occupy the entire app window.

---

# 9. Discover

Discover uses AniList metadata.

Support:

- search
- genre
- season
- year
- format
- status
- trending
- popularity
- score sorting where supported

Use a responsive poster grid.

Search should debounce requests, approximately:

```text
250–350 ms
```

Cancel obsolete requests when query changes.

Do not fire a request for every keystroke.

---

# 10. Anime Detail Screen

This should be one of the visually strongest screens.

First viewport:

- banner/backdrop
- poster
- title
- alternative title if useful
- synopsis
- score
- genres
- format
- year
- studio
- episode count
- airing status
- AniList status/progress

Primary CTA:

```text
Continue Episode 7
```

or:

```text
Play Episode 1
```

Secondary CTA:

```text
Choose Source
```

`Choose Source` must remain available even when Auto Select is enabled.

Below:

- episodes
- related anime
- sequels/prequels
- recommendations

Do not place everything above the fold.

---

# 11. AniList Integration

Use AniList's official GraphQL API.

Create a dedicated typed client.

Do not send GraphQL directly from SwiftUI views.

Support:

- viewer/current user
- search
- anime metadata
- trending
- seasonal anime
- recommendations
- related anime
- user media lists
- progress updates
- status updates

## Media identity

Create:

```swift
struct MediaIdentity: Hashable, Codable {
    let anilistID: Int
    let malID: Int?
    let imdbID: String?
    let tmdbID: Int?
    let kitsuID: String?
}
```

Not every ID will exist.

The architecture must not assume that AniList IDs are accepted by every addon.

Addon adapters should declare which ID namespace they need.

## Authentication

Use a proper desktop OAuth flow.

Prefer:

- `ASWebAuthenticationSession`
- authorization code / PKCE if supported by the current AniList OAuth implementation

Important:

- verify AniList's current OAuth documentation before implementation
- do not embed a confidential client secret in a distributable desktop app
- store access tokens in Keychain
- never log access tokens

---

# 12. Metadata Cache

Create a repository-level cache.

The user should not watch the same poster/details screen refetch every time they navigate back.

Use:

- URLCache for ordinary HTTP where appropriate
- local persisted metadata for frequently accessed anime
- in-memory cache for current session

Use a reasonable freshness policy.

Examples:

```text
Anime static details: hours/days
Trending/seasonal: tens of minutes
User list state: shorter
```

Do not prematurely build a complicated cache invalidation framework.

---

# 13. Addon System

The app must be provider-neutral.

Do not hardcode SeaDex, AnimeTosho, Nyaa, Torrentio, or any other provider directly into core playback logic.

Users should be able to install/configure compatible addons.

Examples of addon-backed sources users may choose themselves:

- SeaDex-like provider
- AnimeTosho-like provider
- Torrentio-compatible provider
- Nyaa-compatible provider
- future providers

The core app provides the protocol, not unauthorized content.

---

# 14. Safe Addon Model

The app should not download arbitrary executable addon code.

Do not:

- execute remote JavaScript
- execute downloaded binaries
- `eval` code
- expose filesystem access
- expose Keychain
- expose Real-Debrid credentials automatically

Prefer network-based addon protocols.

## InstalledAddon

Conceptual model:

```swift
struct InstalledAddon: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String?
    var iconURL: URL?
    var manifestURL: URL
    var baseURL: URL
    var protocolType: AddonProtocolType
    var isEnabled: Bool
    var priority: Int
    var configuration: [String: String]
    var lastHealthStatus: AddonHealthStatus?
}
```

Do not store secrets inside the generic configuration dictionary unless they are separately protected.

---

# 15. Addon Installation UX

Settings → Addons

Tabs/sections:

```text
Installed
Discover
```

Installed example:

```text
≡ SeaDex
  High-quality anime source
  Enabled                     [toggle]

≡ AnimeTosho
  Anime source
  Enabled                     [toggle]

≡ Torrentio
  Multi-index provider
  Enabled                     [toggle]
```

Actions:

- enable/disable
- configure
- remove
- reorder
- health check
- last error/details

Button:

```text
+ Add Addon
```

User enters a manifest URL.

Flow:

1. Validate URL
2. Fetch manifest
3. Enforce timeout
4. Enforce maximum response size
5. Decode strictly
6. Show:
   - name
   - description
   - icon
   - capabilities
   - protocol
7. Ask user to confirm
8. Save

Never silently install a provider.

---

# 16. URL Security

Addon URLs are untrusted user input.

Allow only:

- HTTPS by default
- HTTP only through an explicit Advanced override if needed for local development

Reject:

- `file://`
- executable schemes
- malformed URLs

Prevent accidental access to arbitrary local files.

Be cautious about redirects.

Set request timeouts.

Cap manifest and stream-response sizes.

Do not send cookies, AniList tokens, or Real-Debrid tokens unless specifically required by a user-configured addon flow.

---

# 17. Addon Protocol Architecture

Create an abstraction like:

```swift
protocol StreamAddon: Sendable {
    var descriptor: AddonDescriptor { get }

    func streams(
        for media: MediaIdentity,
        episode: Episode
    ) async throws -> [RawStreamResult]

    func healthCheck() async -> AddonHealthStatus
}
```

Then adapters:

```text
GenericHTTPAddonAdapter
StremioAddonAdapter
```

Do not leak protocol-specific response models into the rest of the app.

Everything eventually becomes:

```text
StreamCandidate
```

---

# 18. Stremio-Compatible Addons

Support Stremio-compatible HTTP addons when practical.

Do not assume an AniList ID can always be passed directly.

Create an identity-resolution layer.

The adapter must:

1. read manifest capabilities
2. identify accepted media ID formats
3. obtain or resolve the required external media ID
4. request streams
5. normalize stream entries
6. never execute addon code

If the required external ID cannot be resolved:

- return a useful error
- do not invent an ID

Do not hardcode a single metadata mapping provider into the domain layer.

---

# 19. Generic HTTP Provider Protocol

Create a simple internal provider protocol that can support future first-party or community providers.

Example manifest concept:

```json
{
  "id": "example.provider",
  "name": "Example Provider",
  "version": "1.0.0",
  "protocol": "anime-stream-v1",
  "capabilities": ["streams"],
  "endpoints": {
    "streams": "/v1/streams"
  }
}
```

Possible stream request:

```json
{
  "anilistId": 52991,
  "malId": 52991,
  "episode": 7,
  "season": 1
}
```

Possible normalized-compatible response:

```json
{
  "streams": [
    {
      "title": "[Group] Anime - 07 [1080p][HEVC]",
      "infoHash": "...",
      "magnetUri": "...",
      "sizeBytes": 1450000000,
      "seeders": 120
    }
  ]
}
```

Do not over-specify this protocol before the first real adapter needs it.

---

# 20. StreamCandidate Domain Model

All provider results become a normalized candidate.

Suggested model:

```swift
struct StreamCandidate: Identifiable, Hashable, Sendable {
    let id: String

    let addonID: String
    let addonName: String

    let displayTitle: String
    let rawTitle: String?

    let infoHash: String?
    let magnetURI: URL?
    let directURL: URL?
    let fileIndex: Int?

    let resolution: VideoResolution?
    let codec: VideoCodec?
    let source: ReleaseSource?
    let releaseGroup: String?

    let sizeBytes: Int64?
    let seeders: Int?

    let audioLanguages: Set<String>
    let subtitleLanguages: Set<String>

    let parsedEpisode: ParsedEpisodeInfo?
    let isBatch: Bool

    var debridStatus: DebridAvailability
    var episodeMatchConfidence: Double

    var scoringBreakdown: StreamScoreBreakdown?
}
```

Do not require every field.

Providers are messy.

Parsing must be defensive.

---

# 21. Release Parsing

Create a dedicated `ReleaseParser`.

Do not put regex directly into `StreamScoringEngine`.

Parse common metadata from release titles.

Recognize at least:

## Resolution

- 2160p
- 1080p
- 720p
- 480p

## Codec

- AV1
- HEVC
- H.265
- x265
- AVC
- H.264
- x264

Normalize aliases.

## Source

- BluRay
- BDRip
- WEB-DL
- WEBRip
- HDTV
- DVD
- CAM
- TS / telesync

## Other

- release group
- dual audio
- dubbed
- batch/complete
- season
- episode
- absolute episode numbering

Keep raw title for debugging.

Create unit tests for every parser rule.

---

# 22. Episode Matching

Wrong episode playback is a critical failure.

Create a dedicated:

```text
EpisodeMatcher
```

It should determine whether a candidate corresponds to the requested episode.

Handle common patterns:

```text
Anime Name - 07
Anime Name - 07v2
Anime Name S01E07
Anime Name S1E7
Anime Name Episode 07
Anime Name 2nd Season - 07
Anime Name [07]
Anime Name - 31
```

Also consider:

- absolute numbering
- split cours
- specials
- OVA
- batches

The matcher should produce:

```swift
struct EpisodeMatchResult {
    let confidence: Double
    let matchedEpisode: Int?
    let reasoning: [EpisodeMatchReason]
}
```

Suggested confidence meaning:

```text
0.95–1.00  extremely strong match
0.85–0.95  good match
0.70–0.85  questionable
<0.70      unsafe for auto selection
```

Do not rely on only one regex.

Use multiple signals:

- parsed episode number
- season
- AniList episode count
- release title normalization
- batch file metadata if available
- provider-provided episode metadata

If confidence is too low:

**do not autoplay**.

Show the source picker.

---

# 23. Multi-Addon Search

When the user wants an episode:

1. obtain all enabled addons
2. query them concurrently
3. use a task group
4. give each provider its own timeout
5. isolate individual failures
6. normalize results
7. parse release metadata
8. match the requested episode
9. deduplicate
10. check debrid availability
11. score
12. auto-select or show source picker

Use structured concurrency.

Conceptual implementation:

```swift
await withTaskGroup(of: AddonQueryResult.self) { group in
    for addon in enabledAddons {
        group.addTask {
            await queryWithTimeout(addon)
        }
    }

    for await result in group {
        ...
    }
}
```

Do not let one provider failure cancel all useful results.

---

# 24. Provider Timeouts

Initial guideline:

```text
Manifest request: ~5 seconds
Stream lookup: ~6–8 seconds per addon
```

Do not block playback indefinitely.

If some providers respond and one is slow:

- proceed with available high-quality results
- optionally continue updating the manual picker if the architecture permits

For Auto Select, it is acceptable to wait a short bounded interval if doing so meaningfully improves confidence.

---

# 25. Deduplication

Different addons may return the same release.

Deduplicate by strongest identifier first:

1. normalized info hash
2. magnet hash
3. direct resource ID if known
4. normalized release title + size + episode as a fallback

When duplicates are merged:

keep metadata about all sources.

Example:

```text
Found via:
SeaDex
AnimeTosho
```

Do not show three visually identical rows.

---

# 26. Debrid Abstraction

Do not make playback logic depend directly on Real-Debrid.

Create:

```swift
protocol DebridService: Sendable {
    func validateAccount() async throws -> DebridAccount
    func checkAvailability(_ candidates: [StreamCandidate]) async throws -> [DebridCheckResult]
    func resolve(_ candidate: StreamCandidate) async throws -> ResolvedStream
}
```

Implement:

```text
RealDebridService
```

first.

Future services may include:

- AllDebrid
- Premiumize
- TorBox

The rest of the app should not care which service is active.

---

# 27. Real-Debrid Integration

Store the Real-Debrid token in Keychain.

Never:

- store it in UserDefaults
- store it in SwiftData
- store it in JSON config
- log it
- send it to addons
- include it in crash messages

Use a dedicated client.

Real-Debrid flow may involve endpoints conceptually similar to:

```text
instant availability
add magnet
select files
torrent info
unrestrict link
```

Before implementation, verify the current official Real-Debrid API documentation and endpoint behavior.

Do not blindly trust this specification if the official API changed.

## Typical resolution flow

For hash/magnet candidates:

```text
candidate
→ instant availability check
→ if cached, prioritize strongly
→ add/resolve torrent if necessary
→ select correct media file
→ obtain generated link
→ unrestrict link
→ playable HTTPS URL
```

For direct addon URLs:

- only send through debrid if the selected service/protocol requires it
- otherwise validate and play directly

---

# 28. Choosing the Correct File Inside a Torrent

A torrent may contain:

- multiple episodes
- extras
- OP/ED videos
- fonts
- subtitles
- sample files

Do not automatically pick the largest file.

When selecting a file:

1. ignore obvious non-video files
2. penalize filenames containing:
   - sample
   - NCOP
   - NCED
   - trailer
   - preview
3. parse episode number from each video filename
4. match requested episode
5. choose the best matching playable video

If only one valid video file exists, use it.

For batch torrents, file-level episode matching is mandatory.

Add tests.

---

# 29. Auto Select Is a Core Feature

Settings → Streaming:

```text
Auto Select Best Stream     ON
```

Description:

> Automatically choose the best available source so playback can start immediately.

Default:

```text
ON
```

The app should support two modes.

## Auto mode

```text
Episode
→ Play
→ source discovery
→ RD check
→ score
→ confidence check
→ playback
```

## Manual mode

```text
Episode
→ source discovery
→ ranked source picker
→ user chooses
→ playback
```

Even when Auto Select is enabled, always provide:

```text
Choose Source
```

---

# 30. Auto-Select Scoring Architecture

Create a dedicated:

```text
StreamScoringEngine
```

It must be deterministic and unit-testable.

Do not scatter scoring conditions across UI code.

Use two phases:

## Phase A — Safety gates

Reject or heavily penalize candidates that fail critical requirements.

Examples:

- wrong episode
- extremely low episode-match confidence
- unusable URL/hash
- unsupported file
- CAM/TS if better sources exist
- corrupted/invalid metadata
- blocked release group

## Phase B — Quality scoring

Rank safe candidates.

The exact values should be configurable internally and easy to tune.

Use a `StreamScoreBreakdown`.

Example:

```swift
struct StreamScoreBreakdown: Sendable {
    var episodeMatch: Double
    var cached: Double
    var resolution: Double
    var source: Double
    var codec: Double
    var size: Double
    var seeders: Double
    var language: Double
    var releaseGroup: Double
    var addonPriority: Double
    var penalties: Double

    var total: Double { ... }
}
```

---

# 31. Initial Scoring Weights

Use these as an initial implementation guideline, not immutable truth.

Critical gate:

```text
episodeMatchConfidence < 0.70
→ never auto-select
```

Strong preference:

```text
episodeMatchConfidence >= 0.90
```

Suggested baseline scoring:

```text
Exact/high-confidence episode match    +35
Real-Debrid cached                     +30
Preferred resolution                   +20
High-quality source                    +10
Preferred audio/subtitle match         +8
Preferred release group                +6
Codec preference                       +4
Sensible file size                     +0..8
Seeder health if uncached              +0..10
Addon priority                         +0..4
```

Penalties:

```text
Questionable episode match             -20 to -100
CAM / TS                               -50
Sample / trailer / NCOP / NCED         -100
Wrong language when required           -20
Extreme unreasonable file size         -5..-20
Known blocked group                    -100
```

The episode match must dominate.

Never let:

```text
better quality
```

override:

```text
wrong episode
```

---

# 32. Cached vs Seeders

Seeder weighting must depend on cache status.

## If cached on Real-Debrid

Seeders should have near-zero importance.

A cached torrent is being served from debrid infrastructure.

Example:

```text
1080p WEB-DL
RD Cached
2 seeders
```

can be preferable to:

```text
1080p WEB-DL
Not cached
500 seeders
```

because the cached source can start immediately.

## If not cached

Seeder health matters much more.

Use a logarithmic score rather than linear.

Conceptual:

```swift
seederScore = min(10, log2(Double(seeders) + 1) * 1.5)
```

Do not let 10,000 seeders overwhelm all other quality signals.

---

# 33. Resolution Preference

Default user setting:

```text
Preferred Quality: Auto
```

Auto should be 1080p-oriented for anime.

Reason:

- 1080p is often the best quality/size tradeoff
- 2160p should not automatically beat an excellent 1080p encode
- 4K anime releases may be upscaled or extremely large

Suggested base scores:

```text
When preference = Auto:

1080p   +20
2160p   +17
720p    +10
480p     +2
unknown   0
```

If preference = 2160p:

```text
2160p   +20
1080p   +13
720p     +5
```

If preference = 1080p:

```text
1080p   +20
2160p   +14
720p    +8
```

Do not hardcode these values in multiple places.

---

# 34. Source Quality

Suggested ranking:

```text
BluRay / BDRip      best
WEB-DL              excellent
WEBRip              good
HDTV                acceptable
DVD                 low
CAM / TS            reject/strong penalty
```

Example scoring:

```text
BluRay    +10
WEB-DL     +9
WEBRip     +7
HDTV       +4
DVD        +1
CAM       -50
TS        -50
```

---

# 35. Codec Preference

Recognize:

- AV1
- HEVC / H.265 / x265
- AVC / H.264 / x264

Do not claim one codec is universally better.

Default scoring should be mild.

The player/device compatibility matters more than codec ideology.

Example default:

```text
HEVC     +4
AV1      +3
AVC      +2
Unknown   0
```

Expose codec preferences only in Advanced settings initially.

---

# 36. File Size Heuristic

Do not choose:

- the smallest file automatically
- the largest remux automatically

Use quality-relative expected ranges.

The goal is a sensible quality-to-size tradeoff.

For a normal ~24 minute anime episode:

rough heuristic only:

```text
< 150 MB       suspicious / strong compression
300–1500 MB    common practical range
1.5–4 GB       high quality / sometimes worthwhile
> 8 GB         likely excessive for default Balanced mode
```

Do not treat these numbers as universal truth.

Long episodes and films must scale by duration.

Prefer using:

```text
bytes per minute
```

when duration is known.

Create:

```text
Quality Preference:
Data Saver
Balanced
Best Quality
```

Default:

```text
Balanced
```

---

# 37. Release Groups

Allow optional preferences.

Advanced settings:

```text
Preferred Release Groups
Blocked Release Groups
```

Do not hardcode a subjective list of "best" anime groups into core logic.

A curated addon such as SeaDex may already provide a quality signal.

If an addon provides a trusted quality ranking, normalize it into candidate metadata rather than building addon-specific logic into the scorer.

---

# 38. Language Preferences

Streaming settings:

```text
Preferred Audio:
Japanese
English
Any

Preferred Subtitles:
English
Spanish
Any
```

Default should be configurable during onboarding or Settings.

Do not automatically reject a stream solely because language metadata is missing.

Unknown metadata is not the same as a mismatch.

---

# 39. Auto-Select Confidence

The scorer should return:

```swift
struct AutoSelectDecision {
    let candidate: StreamCandidate?
    let totalScore: Double
    let confidence: Double
    let scoreGapToSecondPlace: Double?
    let reasons: [String]
    let shouldAutoPlay: Bool
}
```

Confidence should consider:

- episode-match confidence
- metadata completeness
- difference between first and second candidate
- whether the candidate is cached
- whether required language constraints are satisfied
- whether file-level matching succeeded for batches

Suggested default:

```text
Auto-play only if confidence >= ~0.88
```

Tune through tests.

If confidence is too low:

```text
We couldn't confidently choose a source.
```

Show the source picker.

The app should fail safely rather than confidently play the wrong episode.

---

# 40. Source Picker

The source picker should not look like a raw torrent table.

Show useful human-readable information.

Example:

```text
BEST MATCH

★ 1080p · BluRay · HEVC
  1.8 GB · RD Cached
  SeaDex

OTHER SOURCES

1080p · WEB-DL · AVC
1.4 GB · RD Cached
AnimeTosho

2160p · BluRay · HEVC
7.1 GB · RD Cached
Torrentio

1080p · WEB · HEVC
1.1 GB · 86 seeders
Nyaa
```

Prominent:

- resolution
- source
- codec
- size
- cached status

Secondary:

- addon
- release group
- audio
- subtitles

Hidden by default:

- hash
- magnet
- internal IDs

Advanced details can show them.

---

# 41. "Why This Stream?"

Add an optional debug/advanced explanation.

Example:

```text
Why this stream?

✓ Exact episode match
✓ Cached on Real-Debrid
✓ Preferred 1080p quality
✓ BluRay source
✓ Preferred audio
✓ Sensible file size
```

This is valuable for debugging the scoring system.

Do not show it in the normal playback flow.

---

# 42. Streaming Settings

Settings → Streaming

Normal settings:

```text
Auto Select Best Stream        ON

Preferred Quality              Auto
Quality Preference             Balanced

Prefer Cached Streams          ON

Preferred Audio                Japanese
Preferred Subtitles            English

Autoplay Next Episode          ON
```

Advanced:

```text
Preferred Codecs
Preferred Release Groups
Blocked Release Groups

Maximum File Size
Minimum Seeders for Uncached

Addon Weighting
Auto-Select Confidence Threshold

Show Stream Scoring Debug Info
```

Keep normal Settings simple.

---

# 43. Playback Architecture

Create:

```swift
protocol PlayerEngine: AnyObject {
    func load(_ stream: ResolvedStream) async throws
    func play()
    func pause()
    func seek(to seconds: Double)
    func setVolume(_ volume: Double)

    var currentTime: Double { get }
    var duration: Double { get }

    func audioTracks() -> [MediaTrack]
    func subtitleTracks() -> [MediaTrack]
}
```

Use a `PlaybackCoordinator` above the concrete engine.

Do not make player UI depend directly on libmpv APIs.

This allows:

- AVPlayer prototype
- libmpv production engine
- easier testing

---

# 44. AVPlayer vs libmpv

For Phase 1 and UI scaffolding, AVPlayer may be acceptable.

For final anime playback, evaluate libmpv seriously because anime often needs:

- MKV
- ASS / SSA subtitles
- advanced subtitle styling
- multiple audio tracks
- broader codecs

Before adding libmpv:

1. investigate current maintained Swift/macOS integration options
2. verify Apple Silicon
3. verify bundling
4. verify code signing
5. verify redistribution/license obligations
6. verify iPadOS implications if future mobile support matters

Prefer a thin wrapper around libmpv.

Avoid allowing mpv internals to leak through the app.

---

# 45. Player UI

Player should feel premium and minimal.

Normal playback:

- video occupies almost entire view
- controls fade away when idle
- mouse movement reveals them
- timeline
- current time / duration
- volume
- subtitle selection
- audio selection
- playback speed
- fullscreen
- next episode

Keyboard:

```text
Space        Play/Pause
Left         Seek backward
Right        Seek forward
Up           Volume up
Down         Volume down
F            Fullscreen
M            Mute
Esc          Exit fullscreen/player
```

Use familiar seek increments such as:

```text
5 or 10 seconds
```

Make it configurable later if desired.

---

# 46. Subtitles

Anime subtitle support is important.

The production player should support:

- embedded subtitle tracks
- external subtitle URLs/files when provided
- ASS/SSA styling where possible
- SRT
- track switching

Do not convert everything to plain subtitles if it destroys anime typesetting.

If libmpv is selected, use its subtitle support rather than reinventing rendering.

---

# 47. Playback Progress

Persist:

```text
anime ID
episode
position
duration
percentage
updatedAt
```

Update local progress periodically.

Do not write to persistence every frame.

Suggested:

```text
every 10–20 seconds
and on pause/close/seek/end
```

Use throttling.

---

# 48. Episode Completion

Do not mark an episode complete after a few seconds.

Initial threshold:

```text
~88%
```

Also consider:

- remaining seconds
- credits
- short specials

Possible logic:

```text
complete if:
percentage >= 0.88
OR
remainingTime <= 90 seconds and watched substantial duration
```

Keep this logic in a testable service.

---

# 49. AniList Progress Sync

When an episode becomes complete:

- update local state immediately
- then sync AniList
- avoid duplicate updates
- retry temporary network failures

Do not make resume functionality depend on AniList being online.

Local playback state is needed even if AniList is unavailable.

---

# 50. Continue Watching

Continue Watching is based on local playback progress.

If Auto Select is ON:

```text
Resume
→ rediscover sources
→ rank
→ resolve
→ start at saved timestamp
```

The app should not force source selection again unless:

- previous source is unavailable
- confidence is too low
- user explicitly chooses source

Future optimization:

store the previous candidate identity and try it first if still valid.

---

# 51. Next Episode

When the current episode is nearly finished:

show:

```text
Next Episode
Episode 8

Starting in 8…

Play Now      Cancel
```

If Autoplay Next Episode is ON:

start lightweight preparation in the background.

Do not download the next episode video unnecessarily.

Prepare:

- metadata
- provider results
- RD cache check
- candidate ranking

Then playback can start quickly.

---

# 52. Prefetch Strategy

Do not query next-episode providers immediately when playback starts.

Suggested trigger:

```text
when playback reaches ~70–80%
```

or:

```text
when <= 6 minutes remain
```

Whichever comes first, with sensible guards.

Cache the resulting candidate decision briefly.

Cancel prefetch if:

- user stops playback
- user switches anime
- episode changes manually

---

# 53. Settings Architecture

Settings sections:

```text
General
AniList
Streaming
Real-Debrid
Addons
Playback
Advanced
```

Each should be its own focused screen/view.

Do not create one 2,000-line Settings view.

---

# 54. Keychain

Create a small Keychain wrapper.

Store:

- AniList token
- Real-Debrid token
- future sensitive addon credentials

Use meaningful service/account keys.

Example conceptual API:

```swift
protocol SecureStore {
    func set(_ data: Data, for key: String) throws
    func data(for key: String) throws -> Data?
    func delete(_ key: String) throws
}
```

Do not over-engineer.

---

# 55. Persistence

Use SwiftData unless the existing project has another justified persistence layer.

Persist non-sensitive:

- watch progress
- installed addons
- addon order
- user preferences
- cached metadata
- source preferences
- last selected source metadata if useful

Do not persist API secrets there.

Create repositories rather than accessing SwiftData directly from every view.

---

# 56. Logging

Use `Logger`.

Categories:

```text
AniList
Addons
Streaming
Debrid
Playback
Persistence
UI
```

Never log:

- access tokens
- full authorization headers
- private debrid URLs if they contain secrets
- user credentials

Debug logs may include:

- candidate titles
- normalized parser output
- scoring breakdown
- provider timing
- cache hits

---

# 57. Error Handling

Normal errors should be understandable.

Bad:

```text
HTTP 403
```

Good:

```text
Real-Debrid rejected the request.
Check your API token in Settings.
```

Bad:

```text
DecodingError.keyNotFound(...)
```

Good:

```text
This addon returned an unsupported response.
```

Bad:

```text
No streams []
```

Good:

```text
No playable sources were found for this episode.
```

Allow users to open technical details if needed.

---

# 58. Performance

The app should feel fast.

Use:

- async/await
- concurrent provider lookups
- request cancellation
- image caching
- metadata caching
- lazy grids
- lightweight view models
- background parsing/scoring

Do not:

- parse large responses on the main actor
- wait sequentially for every addon
- refetch the same anime repeatedly
- decode giant payloads without limits

---

# 59. Image Loading

For the MVP, prefer a simple image pipeline.

Options:

- `AsyncImage` + URLCache if sufficient
- small custom cached image loader if needed

Do not immediately add a large image framework.

Poster placeholders should preserve layout size to avoid jumping.

Use skeletons during initial loading.

---

# 60. Accessibility

Support:

- keyboard navigation
- VoiceOver labels
- meaningful button labels
- sufficient contrast
- reduced motion
- visible focus states

Respect:

```text
Reduce Motion
```

Do not make critical information available only on hover.

---

# 61. Testing Strategy

The streaming-selection layer must have strong tests.

At minimum test:

## Release parsing

- resolution
- codec
- source
- group
- episode number
- batch detection

## Episode matching

- exact episode
- absolute episode
- season episode
- wrong episode
- batch
- special

## Deduplication

- same info hash from two addons
- same magnet
- normalized duplicate title

## Scoring

- cached vs uncached
- 1080p vs 2160p
- quality source
- size
- seeders
- language
- addon priority
- wrong episode

## Auto-select confidence

- clear winner
- ambiguous top two
- incomplete metadata
- unsafe episode match

## Real-Debrid

- account validation parsing
- instant availability parsing
- resolve flow
- API errors

## Progress

- completion threshold
- resume
- short playback should not complete
- sync retry state

## Addons

- timeout
- malformed JSON
- provider failure isolation
- oversized response
- invalid manifest

---

# 62. Required Scoring Tests

Implement explicit tests similar to these.

## Case 1

Candidate A:

```text
1080p
BluRay
HEVC
RD Cached
1.8 GB
20 seeders
correct episode
```

Candidate B:

```text
2160p
BluRay
HEVC
Not cached
12 GB
2 seeders
correct episode
```

Default Balanced / Auto quality should normally select A.

## Case 2

A:

```text
720p
WEBRip
RD Cached
correct episode
```

B:

```text
1080p
BluRay
RD Cached
correct episode
```

Select B.

## Case 3

A:

```text
1080p
BluRay
RD Cached
wrong episode
```

B:

```text
1080p
WEB-DL
RD Cached
correct episode
```

Always select B.

## Case 4

A:

```text
1080p
WEB-DL
uncached
500 seeders
```

B:

```text
1080p
WEB-DL
RD Cached
2 seeders
```

Prefer B.

## Case 5

A:

```text
1080p
BluRay
RD Cached
episode confidence 0.98
```

B:

```text
1080p
BluRay
RD Cached
episode confidence 0.76
```

Prefer A by a large margin.

## Case 6

A and B are almost equal and both have uncertain episode parsing.

Expected:

```text
shouldAutoPlay = false
```

Show manual picker.

---

# 63. Networking Implementation

Create one reusable HTTP client abstraction.

Conceptual:

```swift
protocol HTTPClient: Sendable {
    func send<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type
    ) async throws -> T
}
```

Features:

- timeout
- status code validation
- maximum response size where possible
- typed decode errors
- cancellation
- configurable headers

Do not build separate ad-hoc URLSession logic for every service.

---

# 64. Timeouts

Create a reusable timeout utility.

Conceptual:

```swift
func withTimeout<T>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T
```

Use it for addon calls.

Do not use detached tasks carelessly.

Keep cancellation structured.

---

# 65. MVP Phases

Follow these phases.

Do not skip ahead unless a dependency requires it.

---

## PHASE 0 — Repository Assessment

Before implementation:

- inspect project
- build current state
- run tests
- report architecture
- report risks
- report what is already implemented

Deliverable:

```text
REPO_ASSESSMENT.md
```

Keep it concise.

---

## PHASE 1 — Premium App Shell + AniList Public Metadata

Build:

- app shell
- sidebar/navigation
- design tokens
- Home
- Discover
- Anime Details
- Library placeholder/state
- Settings shell
- AniList public metadata client
- image loading
- loading/error states
- sample previews

Do not implement real streaming yet.

Use mock playback/source data if needed.

At the end of Phase 1 the app should already look like a credible premium product.

Build and test.

---

## PHASE 2 — AniList Authentication and User Library

Implement:

- OAuth flow
- token storage in Keychain
- viewer
- Watching
- Planning
- Completed
- Paused
- Dropped
- status updates
- progress update foundation

Home should now use real user data.

Build and test.

---

## PHASE 3 — Addon Framework

Implement:

- InstalledAddon persistence
- AddonManager
- addon enable/disable
- ordering
- manifest installation
- validation
- health status
- StreamAddon protocol
- Generic HTTP adapter
- Stremio adapter if technically viable
- mock/test addon
- multi-addon querying

Do not implement Real-Debrid yet.

Use normalized StreamCandidate results.

Build and test.

---

## PHASE 4 — Parsing / Matching / Deduplication

Implement:

- ReleaseParser
- EpisodeMatcher
- StreamDeduplicator
- candidate normalization
- tests

Do not implement auto-play until episode matching is reliable.

Build and test.

---

## PHASE 5 — Real-Debrid

Implement:

- DebridService
- RealDebridService
- Keychain token
- account validation
- cache/availability checking
- resolving
- correct file selection for batch torrents
- friendly errors
- tests

Build and test.

---

## PHASE 6 — Stream Scoring + Auto Select

Implement:

- StreamScoringEngine
- StreamScoreBreakdown
- AutoSelectDecision
- Auto Select setting
- confidence threshold
- cached weighting
- quality weighting
- seeders weighting
- size heuristic
- language preferences
- source picker

This is a critical phase.

Do not call it complete without the explicit scoring tests.

Build and test.

---

## PHASE 7 — Playback

Implement:

- PlayerEngine abstraction
- final player technology decision
- video loading
- controls
- fullscreen
- subtitles
- audio tracks
- keyboard shortcuts
- resume

If libmpv is selected:

- document integration
- document licenses/distribution
- verify signed app build on Apple Silicon

Build and test.

---

## PHASE 8 — Progress + AniList Sync

Implement:

- local progress
- completion threshold
- resume
- AniList sync
- retry on network failure
- Continue Watching

Build and test.

---

## PHASE 9 — Autoplay Next Episode

Implement:

- next episode overlay
- countdown
- Play Now
- Cancel
- pre-resolution
- next-source cache
- cancellation rules

Build and test.

---

## PHASE 10 — Polish

Improve:

- animation
- keyboard navigation
- accessibility
- errors
- caching
- performance
- provider health UI
- debug/source explanation
- test coverage
- onboarding

Only polish after the core flow is reliable.

---

# 66. Onboarding

Eventually create lightweight onboarding.

Suggested:

```text
Welcome

1. Connect AniList
2. Connect Real-Debrid
3. Add streaming addons
4. Choose preferences
```

Do not force every integration.

Users may browse AniList without Real-Debrid configured.

Streaming should explain what is missing.

---

# 67. Empty States

Examples:

## No AniList account

```text
Connect AniList to sync your library and watch progress.
```

## No addons

```text
No streaming addons are configured.

Add an addon to discover sources.
```

## No Real-Debrid

```text
Connect a debrid service to resolve supported streams.
```

## No sources

```text
No playable sources were found for this episode.
```

Do not show blank screens.

---

# 68. Legal / Provider-Neutral Core

The core app should not bundle unauthorized content.

The app provides:

- anime metadata
- playback
- addon interfaces
- user-installed providers
- debrid integrations configured by the user

Do not hardcode questionable third-party piracy endpoints directly into the application.

Do not embed third-party credentials.

Keep providers modular and user-configured.

---

# 69. Security Checklist

Before calling streaming architecture complete, verify:

- [ ] AniList token is in Keychain
- [ ] Real-Debrid token is in Keychain
- [ ] tokens never appear in logs
- [ ] addon URLs are validated
- [ ] no `file://` addon access
- [ ] addon requests have timeouts
- [ ] addon responses have size limits
- [ ] malformed provider JSON does not crash app
- [ ] provider failure does not crash multi-search
- [ ] arbitrary remote JavaScript is never executed
- [ ] remote binaries are never executed
- [ ] addons cannot read local files
- [ ] addons never receive debrid secrets automatically
- [ ] debug logs redact sensitive URLs/headers

---

# 70. Performance Checklist

- [ ] search is debounced
- [ ] obsolete requests are cancelled
- [ ] poster grids are lazy
- [ ] provider queries are concurrent
- [ ] one provider cannot stall all results
- [ ] stream parsing is off main actor
- [ ] scoring is off main actor
- [ ] cache avoids repeated metadata calls
- [ ] progress writes are throttled
- [ ] player updates do not cause whole-screen SwiftUI rerenders every frame

---

# 71. UI Quality Checklist

Before considering a screen complete:

- [ ] loading state exists
- [ ] empty state exists
- [ ] error state exists
- [ ] keyboard navigation works
- [ ] hover behavior is sensible
- [ ] resizing does not break layout
- [ ] artwork keeps correct aspect ratio
- [ ] text truncates gracefully
- [ ] no unnecessary borders
- [ ] spacing uses design tokens
- [ ] typography has clear hierarchy
- [ ] controls have accessibility labels
- [ ] dark appearance looks intentional
- [ ] screen does not look like an admin dashboard

---

# 72. Code Quality Rules

Use:

- strong typing
- small cohesive components
- clear names
- testable services
- explicit error types
- async/await
- actors where concurrency genuinely requires isolation

Avoid:

- `Any` unless absolutely necessary
- force unwraps
- force casts
- 1,000-line views
- giant service classes
- logic duplicated across screens
- direct API calls from views
- giant switch statements for addon-specific behavior
- global mutable state
- premature generic abstractions
- comments that just restate code

Comments should explain **why**, not **what**, when the reason is non-obvious.

---

# 73. Git / Change Discipline

For each phase:

1. make focused changes
2. build
3. test
4. fix
5. only then continue

Do not modify unrelated parts of the project.

Do not delete tests to make the build green.

Do not silence compiler warnings without understanding them.

Do not disable Swift concurrency checks merely to avoid fixing issues.

---

# 74. Build Verification

Use the project's real scheme and configuration.

Typical command:

```bash
xcodebuild \
  -scheme "<DetectedScheme>" \
  -destination "platform=macOS" \
  build
```

Tests:

```bash
xcodebuild \
  -scheme "<DetectedScheme>" \
  -destination "platform=macOS" \
  test
```

Determine the actual scheme first.

Do not blindly paste placeholder scheme names into scripts.

---

# 75. What Not To Build Yet

Do not spend MVP time on:

- social features
- comments
- chat
- custom profile systems
- achievements
- multiple themes
- plugin code execution
- torrent-client management UI
- full media-server functionality
- giant analytics dashboards
- complicated recommendation ML
- cloud accounts unrelated to AniList
- sync infrastructure beyond what is necessary

The core experience matters more:

```text
Discover
→ Play
→ correct high-quality stream
→ seamless resume
```

---

# 76. Definition of a Good V1

V1 is successful if:

1. App feels polished and native.
2. AniList browsing works.
3. User can connect AniList.
4. User can add compatible addons.
5. Addons can return stream candidates safely.
6. User can connect Real-Debrid.
7. App correctly recognizes the requested episode.
8. Auto Select usually picks a strong cached source.
9. Low-confidence cases fall back to manual source selection.
10. Playback handles common anime files/subtitles reliably.
11. Progress resumes correctly.
12. AniList progress updates.
13. Next episode playback is smooth.
14. One broken addon does not break the app.
15. No credentials are stored insecurely.

---

# 77. First Task — Do This Now

Do not begin with Real-Debrid.

Do not begin with libmpv.

Do not begin by implementing provider scraping.

Start with this exact sequence:

## Step 1

Inspect the repository.

Report:

- project type
- Swift version
- deployment target
- current dependencies
- current architecture
- existing screens
- existing tests
- build status
- obvious technical debt

## Step 2

Propose the architecture you will actually use.

Keep it concise.

Explain any deviations from this document.

## Step 3

Define the minimum domain models needed for Phase 1:

- `Anime`
- `Episode`
- `MediaIdentity`
- `PlaybackProgress`
- `InstalledAddon`
- `StreamCandidate`

Do not overfill them with speculative fields.

## Step 4

Define the design tokens and reusable UI primitives.

## Step 5

Implement Phase 1:

- root app shell
- navigation
- Home
- Discover
- Anime Details
- Library shell
- Settings shell
- AniList public metadata
- loading/error/empty states

## Step 6

Build.

## Step 7

Run tests.

## Step 8

Fix all new errors.

## Step 9

Summarize:

```text
Completed
Changed files
Build result
Tests
Known limitations
Next recommended step
```

Then stop before Phase 2 unless explicitly instructed to continue.

---

# 78. Final Product Principle

Keep returning to this principle:

> Complexity belongs underneath the interface, not in front of the user.

The normal experience should feel like:

```text
Open app
→ choose anime
→ Play
→ watch
```

not:

```text
Open app
→ choose indexer
→ inspect torrents
→ compare seeders
→ check cache
→ select hash
→ select file
→ resolve debrid
→ play
```

Advanced users should have access to:

```text
Choose Source
```

and detailed stream information.

Everyone else should be able to leave:

```text
Auto Select Best Stream = ON
```

and get a Netflix/Crunchyroll-like experience.

When Auto Select is safe and confident, make it invisible.

When it is uncertain, do not guess.

Ask the user to choose.

Correctness beats false confidence.
