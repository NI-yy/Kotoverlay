# Kotoverlay implementation plan

This plan intentionally separates technical risks so that every phase produces
an independently testable result. A phase is complete only after its exit
criteria pass on the reference M2 / 8 GB Mac and in CI where applicable.

## Scope for the first usable release

The first usable release targets the Discord desktop application on macOS and
translates visible English messages into Japanese using `qwen3:1.7b` through a
local Ollama API.

In scope:

- Automatic Discord process and window detection.
- Accessibility-first extraction of visible messages.
- Local translation, cancellation, deduplication, and caching.
- A translation panel that follows the Discord window.
- Optional in-place overlays after panel behavior is stable.
- Vision OCR only when Accessibility does not expose usable text.

Not in the first release:

- Translating voice channels or audio.
- Sending messages or automating Discord input.
- Cloud translation providers.
- Windows, Linux, iOS, or Android support.
- Mac App Store distribution.

## Phase 0: Repository and automation baseline

Goal: make every subsequent change reviewable and automatically verifiable.

Deliverables:

- Repository documentation, license, contribution policy, and issue templates.
- A macOS GitHub Actions workflow with read-only token permissions.
- A local CI entry point shared by developers and GitHub Actions.

Verification:

- `./Scripts/ci.sh` succeeds before any Swift target exists.
- The workflow runs on pushes and pull requests.

Exit criteria:

- `main` is green and contains no local paths, captures, credentials, or models.

## Phase 1: Accessibility feasibility spike (`AXProbe`)

Goal: prove that Discord exposes enough visible message text and geometry to
avoid continuous OCR.

Deliverables:

- A Swift Package with `KotoverlayCore` and an `axprobe` executable.
- Discord process and main-window discovery by bundle identifier.
- Bounded Accessibility traversal with timeout and cancellation.
- Debug output containing role, value, frame, and a stable synthetic identifier.
- Permission-state reporting without repeatedly prompting the user.

Manual scenarios:

1. Discord absent.
2. Discord running with no Accessibility permission.
3. Permission granted while `axprobe` is running.
4. Channel switching, scrolling, window resizing, minimizing, and multiple
   Discord windows.

Exit criteria:

- Visible message text and screen coordinates can be identified reliably, or a
  written decision records why OCR must become the primary extractor.
- One scan completes in under 250 ms on the reference machine.
- The traversal cannot hang Discord or the CLI.

## Phase 2: Local translation spike (`kotoverlay-cli`)

Goal: validate translation quality, latency, cancellation, and local-only
network behavior independently of Discord extraction.

Deliverables:

- `TranslationProvider` protocol.
- `OllamaTranslationProvider` using `URLSession` and `127.0.0.1:11434`.
- Health check, model discovery, streaming response parsing, timeout, and
  cancellation.
- Prompt rules that preserve code, URLs, user names, API names, and formatting.
- A CLI that accepts synthetic English text and prints Japanese.
- A mock HTTP transport for CI; CI must not install Ollama or download a model.

Exit criteria:

- Synthetic graphics-programming examples produce translation-only responses.
- A cancelled request releases its task promptly.
- Missing server, missing model, malformed stream, and timeout cases have tests.
- Median short-message latency is recorded on the reference machine.

## Phase 3: Core live pipeline

Goal: combine extraction and translation without a graphical overlay.

Deliverables:

- `DetectedText`, `MessageIdentity`, `TranslationRequest`, and
  `TranslationResult` value types.
- English detection and filtering for UI labels, code-only text, and duplicates.
- An actor-owned queue with bounded concurrency and newest-visible priority.
- In-memory cache followed by a versioned persistent cache.
- Structured diagnostics that omit captured text by default.

Exit criteria:

- Scrolling through a channel translates each unchanged message at most once.
- Old work is cancelled when the channel changes.
- Reopening the same channel uses cached results.
- Unit tests cover ordering, deduplication, cancellation, and cache migration.

## Phase 4: Discord-following translation panel (first usable UI)

Goal: provide a robust daily-use interface before attempting exact overlays.

Deliverables:

- A menu-bar macOS application.
- Onboarding for Accessibility permission and Ollama/model readiness.
- A companion panel that follows Discord position, size, visibility, and Spaces.
- Start, pause, retry, clear-cache, and diagnostics controls.
- Original/translation pairing without capturing mouse or keyboard input meant
  for Discord.

Exit criteria:

- The panel survives Discord relaunch, minimize/restore, resize, and channel
  switching.
- Closing the panel stops scanning and translation work.
- No message content is written to logs without an explicit diagnostic option.

## Phase 5: In-place overlay

Goal: place translations above source message regions without interfering with
Discord interaction.

Deliverables:

- Click-through transparent `NSPanel` windows.
- Coordinate conversion across screens, backing scales, and menu-bar/Dock
  arrangements.
- Overlay reuse keyed by message identity to avoid flicker.
- Hover or shortcut-based access to original text.
- Automatic hiding for stale, occluded, minimized, or off-screen content.

Exit criteria:

- Overlays follow scrolling and resizing without blocking Discord clicks.
- No overlay is captured recursively by the extraction pipeline.
- Multi-display and Retina/non-Retina transitions are manually verified.

## Phase 6: ScreenCaptureKit and Vision fallback

Goal: translate content that Discord does not expose through Accessibility.

Deliverables:

- Screen Recording permission onboarding separate from Accessibility onboarding.
- Discord-window-only capture through ScreenCaptureKit.
- Change detection and cropped Vision text recognition.
- Confidence filtering and coordinate normalization.
- A policy that uses OCR only for missing Accessibility regions.

Exit criteria:

- OCR is disabled when Accessibility provides sufficient text.
- Capture is limited to Discord and never written to disk by default.
- OCR remains responsive at a capped rate of at most 2 scans per second.

## Phase 7: Reliability, performance, and privacy hardening

Goal: make long-running use predictable on an 8 GB Mac.

Deliverables:

- Instruments profiles for idle, scrolling, translation, and OCR workloads.
- Backpressure, memory limits, cache pruning, and model-unavailable recovery.
- A privacy threat model and data-flow audit.
- Synthetic end-to-end fixtures for Accessibility and OCR outputs.
- Accessibility labels and keyboard control for Kotoverlay itself.

Release targets:

- Idle CPU below 2% while Discord content is unchanged.
- No unbounded queue, cache, overlay, or screenshot growth.
- No outbound connection except loopback in the default configuration.
- Clean recovery after Discord or Ollama restarts.

## Phase 8: Packaging and release automation

Goal: publish reproducible GitHub releases without committing secrets.

Deliverables:

- Versioning and changelog policy.
- Unsigned development artifacts for internal verification.
- Optional Developer ID signing and Apple notarization after enrolling in the
  Apple Developer Program.
- A tagged release workflow with protected GitHub environments and minimal token
  permissions.
- SHA-256 checksums and generated release notes.

Exit criteria:

- CI builds and tests every pull request.
- Release automation is dry-run tested without production credentials.
- A clean Mac can install, grant permissions, connect to Ollama, and remove the
  application using documented steps.

## Recommended issue order

1. Bootstrap Swift package and shared schemes.
2. Implement Accessibility permission state.
3. Build the `AXProbe` Discord traversal.
4. Define core message and geometry types.
5. Implement the Ollama provider and mock transport.
6. Build the translation CLI.
7. Implement deduplication, queueing, and cache.
8. Create the menu-bar app and onboarding.
9. Build the Discord-following companion panel.
10. Implement in-place overlays.
11. Add ScreenCaptureKit capture.
12. Add Vision OCR fallback.
13. Run performance and privacy hardening.
14. Add release packaging and notarization support.

Issues 2-3 and 5-6 can proceed independently after issue 1. UI work starts only
after the relevant extraction and translation exit criteria pass.
