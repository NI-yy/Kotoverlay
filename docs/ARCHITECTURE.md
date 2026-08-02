# Architecture

## Design constraints

- macOS-native implementation in Swift.
- The core must run without a GUI for deterministic testing.
- Accessibility is the primary extractor; OCR is a fallback.
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
└── Translation and live-pipeline validation

Kotoverlay.app (SwiftUI + AppKit)
├── MenuBarAndSettings
├── PermissionOnboarding
├── CompanionPanel
└── InPlaceOverlay
```

## Data flow

```text
NSWorkspace / Accessibility notifications
  -> Discord application and window snapshot
  -> visible text candidates with screen-space rectangles
  -> normalization, language filter, and stable identity
  -> cache lookup
  -> bounded translation scheduler
  -> TranslationProvider (Ollama initially)
  -> cache update
  -> presentation snapshot on the main actor
```

When a usable Accessibility value or frame is missing:

```text
Discord SCWindow
  -> ScreenCaptureKit frame
  -> changed regions
  -> Vision OCR
  -> the same normalization and translation pipeline
```

## Core interfaces

The concrete signatures will be decided during implementation, but these
boundaries are mandatory:

- `TextExtractor`: produces visible text snapshots without translation logic.
- `TranslationProvider`: translates normalized requests and supports
  cancellation.
- `TranslationCache`: stores versioned results without knowing UI details.
- `OverlayPresenter`: receives immutable presentation snapshots.
- `Clock` and `HTTPTransport`: injectable for deterministic tests.

## Concurrency model

- UI and window mutation run on `MainActor`.
- Accessibility traversal is bounded and performed off the main actor.
- One actor owns message identity, pending work, cache state, and generation
  numbers.
- A channel/window generation invalidates older translation tasks.
- Translation concurrency starts at one for the M2 / 8 GB reference machine.
- OCR and Accessibility scans use independent rate limits.

## Identity and caching

Discord may recycle accessibility elements while scrolling. Object identity is
therefore not sufficient. A message identity should combine normalized text,
author when available, nearby structure, and a channel/window generation. The
cache key also includes source language, target language, model identifier, and
prompt version so that model or prompt changes cannot return stale translations.

## Permissions

- Accessibility permission is requested first and is sufficient for the primary
  extraction path.
- Screen Recording permission is requested only when OCR fallback is enabled.
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
