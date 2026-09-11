# REPO_ASSESSMENT.md

Phase 0 — Repository Assessment
Date: 2026-09-11
Branch: `master` (no commits yet)

## 1. Repository state

Greenfield. The repository contains exactly one tracked-or-untracked file:

```text
anime_app_opencode_master_prompt.md   (untracked)
```

No Xcode project, workspace, SPM manifest, source files, tests, assets, CI,
README, `.gitignore`, or licensing files exist. There is no prior architecture
to preserve and no technical debt.

## 2. Toolchain (verified)

| Item | Value |
|---|---|
| OS | macOS 26.6 (25G5028f), Apple Silicon (arm64) |
| Xcode | 26.2 (17C52) |
| Swift | 6.2.3 (swiftlang-6.2.3.3.21) |
| macOS SDK | 26.2 |
| Project generator | XcodeGen 2.44.1 via Homebrew |
| Code signing | Apple Development identity present |
| Missing tools | tuist, SwiftLint, SwiftFormat, xcbeautify (none required) |

## 3. Build and test status

- **Build:** not applicable — no targets or schemes exist; `xcodebuild` has
  nothing to build.
- **Tests:** none.
- Consequently, Phase 0's "build current state" is satisfied by toolchain
  validation only. No build/test failure exists to fix.

## 4. Already implemented

Nothing product-facing. The master prompt is the only artifact.

## 5. Proposed Phase 1 architecture

Follow the master prompt's `§4` tree, creating only what Phase 1 needs:

```text
project.yml                      (XcodeGen spec, checked in)
AnimeStreaming/
    App/                         AppEntry, AppEnvironment, AppRouter, RootView
    Core/Domain/                 Anime, Episode, MediaIdentity, PlaybackProgress,
                                 InstalledAddon, StreamCandidate
    Core/Networking/             HTTPClient, HTTPError, RequestBuilder
    Core/Logging/                AppLogger
    Core/Persistence/            (minimal in Phase 1)
    Services/AniList/            AniListClient, AniListModels, AniListRepository
    Features/Home, Discover, AnimeDetails, Library, Settings/
    DesignSystem/                DesignTokens, Typography, Components/
AnimeStreamingTests/             Swift Testing fixtures
```

Conventions:

- State: `@Observable @MainActor` view models; `actor` for shared caches.
- DI: a plain `AppEnvironment` container; no framework.
- Networking: one `HTTPClient` over `URLSession`, typed errors, timeouts,
  response-size caps, cancellation.
- Persistence: SwiftData for non-sensitive data only; Keychain for secrets.
- Logging: `OSLog` `Logger` with the `§56` categories; secrets redacted.
- Concurrency: Swift 6 language mode with strict concurrency checks.
- Tests: Swift Testing (ships with Xcode 26); no live network in unit tests.
- Project generation: XcodeGen `project.yml`; the generated `.xcodeproj` is
  git-ignored so generated binaries never enter history.

## 6. Deviations from the specification (with reasons)

1. **XcodeGen instead of a hand-created project.** Build tooling only, not a
   shipped dependency; already installed; produces a reproducible project and
   avoids fragile hand-edited `.pbxproj` diffs.
2. **Fixture-backed metadata repository seam.** The AniList API is currently
   disabled (see risk 7.1). AniList remains the primary source, but Phase 1 UI
   development, previews, and tests run against a fixture provider so progress
   does not depend on an external outage. No second production metadata source
   is added.
3. **Deployment target: macOS 15.0** (recommended; not specified in the
   prompt). Gives mature Observation/SwiftData/Swift 6 support while allowing
   macOS 26-only APIs (e.g. Liquid Glass) behind `#available`.
4. **App menu bar** included in the shell from Phase 1 (native macOS
   convention; required for menu command discovery and keyboard shortcuts).

## 7. Risks

### 7.1 CRITICAL — AniList API is currently disabled

Live check on 2026-09-11: `POST https://graphql.anilist.co` returns HTTP 403
for every query:

```text
"The AniList API has been temporarily disabled due to severe stability issues."
```

AniList's documentation confirms this is an intentional suspension during
outages, with no ETA. This blocks live verification for Phase 1 (public
metadata) and Phase 2 (OAuth/user lists). Mitigation: architecture keeps a
repository seam so UI work proceeds on fixtures; re-verify availability before
Phase 2. Do not fake live success in tests.

### 7.2 HIGH — Player technology (Phase 7)

AVPlayer cannot reliably play MKV/ASS-styled anime releases; libmpv adds
licensing (LGPL/GPL), bundling, signing, and notarization obligations. The
`PlayerEngine` abstraction keeps this decoupled, but a dedicated spike is
needed before committing to libmpv. iPadOS feasibility must be part of it.

### 7.3 HIGH — Streaming correctness

Wrong-episode playback is the highest-impact failure mode. Mitigation is
mandatory per `§61`/`§62`: parser, matcher, dedupe, scorer, and confidence
tests before any auto-play.

### 7.4 MEDIUM — Untrusted addon input

Addon URLs are user input. Enforce HTTPS-only (with explicit dev override),
timeouts, response-size caps, strict decoding, no secret forwarding, and no
code execution, per `§16`.

### 7.5 MEDIUM — Swift 6 strict concurrency

Task groups, actors, and Sendable boundaries will surface compile-time
isolation errors; budget time rather than disabling concurrency checks.

### 7.6 MEDIUM — External API verification debt

Verify current AniList OAuth (Phase 2) and Real-Debrid (Phase 5)
documentation before implementing; the specification explicitly requires this.
Never embed a client secret in a desktop app.

### 7.7 LOW — Repository hygiene

No `.gitignore`, README, or CI. Add `.gitignore` (Xcode, SPM, XcodeGen output)
in Phase 1. The master prompt file is untracked; an initial commit is
recommended once the user approves.

## 8. Installed agent skills

Selected for this project: `swiftui-pro`, `swift-concurrency`,
`swift-testing-pro`, `swiftdata-pro`, `swiftui-performance-audit`,
`macos-design-guidelines`. They supplement, never override, the master prompt.

## 9. Phase 1 readiness checklist

- [x] `project.yml` + generated macOS app target and unit-test target
- [x] Design tokens and core components (poster card, buttons, states)
- [x] App shell: sidebar (Home, Discover, Library) + Settings
- [x] AniList client/repository with fixture-backed alternate
- [x] Home, Discover, Anime Details, Library shell, Settings shell
- [x] Loading / empty / error states everywhere
- [x] Cached async image loading with stable layout placeholders
- [x] Build green (`xcodebuild -scheme ... -destination platform=macOS build`)
- [x] Tests green (`xcodebuild ... test`)

## 10. Final status (all phases complete)

Built through Phase 10 of the master prompt:

| Phase | Scope | Status |
|---|---|---|
| 0 | Repository assessment | Done |
| 1 | App shell + design system + AniList public metadata | Done |
| 2 | AniList OAuth (implicit grant), Keychain, user library | Done |
| 3 | Addon framework (generic + Stremio adapters, SwiftData registry, install flow) | Done |
| 4 | ReleaseParser / EpisodeMatcher / StreamDeduplicator / StreamNormalizer | Done |
| 5 | Real-Debrid (Keychain token, availability probe, resolve, batch file selection) | Done |
| 6 | StreamScoringEngine, AutoSelectDecision, source picker + "Why this stream?" | Done |
| 7 | Playback (PlayerEngine + AVPlayerEngine, PlaybackCoordinator, player UI) | Done |
| 8 | SwiftData progress, completion threshold, Continue Watching, AniList sync with retry | Done |
| 9 | Next-episode prefetch, countdown overlay, autoplay + cancellation | Done |
| 10 | Onboarding, provider health check-all, player render isolation, debug details | Done |

Verification at completion:

- Signed build succeeds; app launches and quits cleanly.
- All content comes from the live AniList API: public (unauthenticated) by default,
  with authenticated requests used automatically when the user connects their
  AniList account. No sample/placeholder catalog exists in the app target.
- 330 unit tests in 41 suites pass.
- Security: AniList + Real-Debrid tokens in Keychain only, never logged; addon URLs
  HTTPS-only with timeouts/size caps; no remote code execution.

Known limitations carried into a future release:

- **AniList API is restricted, not globally disabled.** Verified 2026-09-11: requests
  without a `Referer` header receive the misleading 403 "temporarily disabled"
  envelope from AniList's WAF (server: cloudflare), while requests with any `Referer`
  succeed from the same IP. The app now sends `Referer: com.auax.AnimeStreaming`;
  live trending and anime-details fetches through the real client were verified
  working. AniList remains in a degraded state (docs mention a 30 req/min limit), so
  behavior may change again.
- **Playback engine.** MPVPlayerEngine (MPVKit 1.0.0, LGPL target) is now the
  default, and AVPlayerEngine remains selectable under Settings → Playback as a
  fallback. Verified 2026-09-11 on Apple Silicon: remote HTTPS MP4 and MKV
  playback, seeking, pause/resume, volume, speed, HEVC/VideoToolbox hardware
  decoding (`hwdec=auto-safe`), embedded multiple audio tracks, and embedded
  ASS/SSA subtitle tracks. The app bundles only the LGPL MPVKit product; the
  GPL product is not linked. Distribution still requires the LGPL notice/relink
  obligations to be shipped with the app.
- Real-Debrid availability probing uses the add/select/inspect/delete workaround
  because `/torrents/instantAvailability` was removed by Real-Debrid.
- Stremio addons require ID namespaces the app can resolve; no external ID mapping
  provider is bundled.

