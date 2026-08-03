# Architecture

## Design constraints

- macOS-native implementation in Swift.
- The core must run without a GUI for deterministic testing.
- ScreenCaptureKit and Vision OCR are the primary Discord content extractor.
- Accessibility is retained for application/window diagnostics and metadata.
- Captured content is sensitive and remains in memory unless cache is explicitly
  enabled.
- Ollama integration is replaceable and restricted to loopback by default.
- UI, extraction, and inference failures must not block each other.

## Targets

```text
KotoverlayCore (Swift library)
├── ApplicationDiscovery
├── AccessibilityExtraction
├── CaptureAndOCR
├── LanguageFiltering
├── Translation
├── SchedulingAndCaching
└── Diagnostics

axprobe (Swift executable)
└── Accessibility feasibility and debug inspection

kotoverlay-cli (Swift executable)
└── Isolated translation validation

pipelineprobe (Swift executable)
└── Combined Discord OCR, filtering, scheduling, caching, and translation

Kotoverlay.app (SwiftUI + AppKit)
├── MenuBarAndSettings
├── PermissionOnboarding
├── CompanionPanel
└── InPlaceOverlay
```

## Data flow

```text
NSWorkspace / Accessibility diagnostics
  -> Discord application and window selection
  -> ScreenCaptureKit window frame
  -> changed regions
  -> Vision OCR text candidates with screen-space rectangles
  -> normalization, language filter, and stable identity
  -> cache lookup
  -> bounded translation scheduler
  -> TranslationProvider (Ollama initially)
  -> cache update
  -> presentation snapshot on the main actor
```

The Accessibility tree is not used as the source of Discord message bodies; see
[ADR 0001](decisions/0001-use-ocr-for-discord-content.md).

## Core interfaces

The concrete signatures will be decided during implementation, but these
boundaries are mandatory:

- `TextExtractor`: produces OCR text snapshots without translation logic.
- `TranslationProvider`: translates normalized requests and supports
  cancellation.
- `TranslationCache`: stores versioned results without knowing UI details.
- `OverlayPresenter`: receives immutable presentation snapshots.
- `Clock` and `HTTPTransport`: injectable for deterministic tests.

## Concurrency model

- UI and window mutation run on `MainActor`.
- Window capture and OCR are bounded and performed off the main actor.
- One actor owns message identity, pending work, cache state, and generation
  numbers.
- A channel/window generation invalidates older translation tasks.
- Translation concurrency starts at one for the M2 / 8 GB reference machine.
- OCR and Accessibility scans use independent rate limits.

## Identity and caching

Vision observations are recreated whenever the captured image changes. Object
identity is therefore not sufficient. A message identity should combine
normalized text, author when available, nearby structure, and a channel/window
generation. The cache key also includes source language, target language, model
identifier, and prompt version so that model or prompt changes cannot return
stale translations.

## Permissions

- Screen Recording permission is required for the primary extraction path.
- Accessibility permission is optional for diagnostics and future window
  metadata enhancements.
- Permission denial is a supported state with clear recovery instructions.
- Bundle identifier and signing identity remain stable during local development
  to reduce repeated permission prompts.

## Privacy and security

- Default Ollama endpoint is exactly `http://127.0.0.1:11434`.
- Redirects and non-loopback endpoints are rejected unless a future explicit
  advanced setting permits them.
- Raw screenshots are not persisted.
- Logs use hashes, counts, timings, and error categories rather than message text.
- GitHub Actions use synthetic fixtures and mocked translation responses.
- Signing and notarization credentials, if added, live only in protected GitHub
  environments and never run for pull requests.

## Distribution direction

Development uses local Xcode signing. The intended public distribution path is a
Developer ID-signed and notarized app published through GitHub Releases. Mac App
Store distribution is not a first-release goal because the app requires broad
interaction with another application's visible content.
