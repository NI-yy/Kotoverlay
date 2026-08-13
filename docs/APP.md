# Kotoverlay menu-bar application

Phase 4 introduces the first macOS `.app`: a menu-bar controller and a companion
translation panel positioned beside Discord. It uses the same tested
ScreenCaptureKit, Vision, scheduler, cache, and Ollama components as the command
line probes.

## Build and run

1. Open `Kotoverlay.xcodeproj` in Xcode.
2. Select the shared `Kotoverlay` scheme and **My Mac** destination.
3. Run the Debug configuration. Xcode's local development signing keeps the
   bundle identifier `dev.niyy.Kotoverlay` stable for privacy permissions.
4. Click the `character.bubble` item in the menu bar.

The generated project is committed, so XcodeGen is not required to build. After
changing `project.yml` or adding application files, regenerate it with:

```sh
xcodegen generate
```

CI builds the shared scheme with signing disabled:

```sh
xcodebuild \
  -project Kotoverlay.xcodeproj \
  -scheme Kotoverlay \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Onboarding and controls

The menu shows readiness for:

- **Screen Recording** — required for Discord-window-only capture.
- **Ollama / selected model** — required and checked through loopback only.
- **Discord** — required to start; a visible desktop window must exist.
- **Accessibility** — optional and retained for diagnostics, not message text.

Available controls are Start, Pause, Retry, Clear Cache, Copy Diagnostics,
Settings, and Quit. Closing the companion panel pauses capture and translation.
Retry refreshes readiness and resumes when all required services are available.

Settings lists models already installed in Ollama. `qwen3:1.7b` is currently
validated and selected by default. Other installed models, including
`qwen3:4b`, can be selected for manual comparison. Changing the model pauses the
current scan and keeps cache entries separate by model. The application does
not download, create, or remove models.

## Display modes

While running, Kotoverlay captures at a maximum of twice per second. Unchanged
frames skip OCR. Changed frames supersede older translation work, so channel
switches and scrolling cannot publish stale results.

After four unchanged captures, the capture cadence reduces from twice per second
to once per second. Any changed frame immediately restores the faster cadence.
If Discord or Ollama is unavailable, retries use a capped delay instead of
continuing full-speed capture and inference work. Discord capture resumes after
the window returns. An Ollama reconnect resets change detection and translates
the still-visible snapshot again without requiring the Retry button.

Each OCR snapshot submits at most the 32 newest eligible messages. The in-memory
translation cache retains at most 512 entries, and the opt-in persistent cache
retains at most 2,000 entries. Older persistent entries and least-recently-used
memory entries are pruned automatically.

Translations are published progressively, newest visible text first. The panel
does not wait for every visible message to finish before showing the first
result. On the reference Apple-silicon Mac with `qwen3:1.7b`, manual verification
reduced time to first translation from about five seconds to under one second.
Total completion time still depends on the number and length of visible messages.

Adjacent OCR lines that appear to belong to one Discord message are grouped into
one translation request. Isolated author labels and Discord metadata are removed
before translation, and the local prompt includes a small GPU terminology
glossary. These heuristics improve context but deliberately keep indented replies
and visually separate messages independent.

The **Companion panel** mode uses a non-activating utility panel that:

- follows the Discord window's current screen-space frame;
- prefers the right side, falls back to the left, and clamps to the visible
  screen area;
- moves without activating Kotoverlay or intercepting input inside Discord;
- hides while Discord is absent, minimized, or not shareable;
- returns after Discord becomes visible or relaunches;
- can appear in full-screen and Space transitions;
- presents original and Japanese text together.

The **In-place overlay** mode places translations directly above the matching
Discord OCR regions. Each borderless `NSPanel`:

- ignores mouse events so Discord remains clickable and scrollable;
- is reused by stable message identity to avoid unnecessary window churn;
- is excluded from ScreenCaptureKit sharing to prevent recursive capture;
- follows Discord movement and resize using source-window-relative coordinates;
- disappears when Discord is not frontmost or when its source is stale,
  off-screen, or too close to another overlay;
- shows one compact line to preserve the association with its source text;
- switches to the original English text while Option is held, or permanently
  when enabled in Settings.

Small collisions may move by at most 12 points. A translation that would need a
larger displacement is hidden instead of being attached visually to the wrong
message. This policy fixed the dense long-message overlap observed during the
first Phase 5 manual trial.

## Privacy

- Only the selected Discord window is captured.
- Captured images stay in memory and are never written by the application.
- Message content is not printed to logs or copied by diagnostics.
- Ollama traffic is restricted to `http://127.0.0.1:11434`.
- Translations are cached in memory by default.
- **Keep translations between launches** is off by default. When explicitly
  enabled, translated text is stored at
  `~/Library/Application Support/Kotoverlay/translations-v2.json`.
- **Clear Cache** removes both memory and persistent entries.

## Manual verification matrix

Before merging Phase 4, verify on the reference Mac:

1. Launch with Screen Recording denied; the menu explains the required action.
2. Grant permission, restart if macOS requests it, and confirm readiness.
3. Start with Discord and Ollama available; translations appear beside Discord.
4. Scroll and switch channels; stale work does not replace the latest results.
5. Resize and move Discord between displays; the panel remains visible and
   adjacent.
6. Minimize/restore and quit/relaunch Discord; the panel hides and recovers.
7. Change Spaces and enter/leave full screen; panel visibility follows Discord.
8. Pause and close the panel; scanning and translation stop.
9. Copy Diagnostics; verify it contains states/counts but no message content.
10. Enable persistent caching, relaunch, verify reuse, then Clear Cache.
11. Switch between installed `qwen3:1.7b` and `qwen3:4b`; verify readiness,
    model-specific cache behavior, latency, and translation quality.
12. Quit and relaunch Discord while scanning; verify capture resumes by itself.
13. Quit and relaunch Ollama while scanning; verify the menu reports waiting and
    the unchanged visible Discord messages are translated after reconnection.
14. Leave Discord unchanged for several seconds, then scroll; verify the first
    update arrives within the one-second idle polling interval.

Automated tests cover panel coordinate conversion and placement, plus the core
filtering, progressive delivery, ordering, cancellation, bounded concurrency,
and cache behavior. The initial reference-screen check reduced 49 raw candidates
to 19 after removing the dense Discord member column; later filtering also
removes common author, role, mention-only, reply-header, and timestamp regions.

## Phase 5 manual verification

The reference Mac verification confirmed that compact in-place translations:

- align with their source lines closely enough to identify the corresponding
  Discord message;
- no longer cascade over adjacent long messages;
- remain visible and readable while Discord is used normally;
- retain click-through behavior.

Multi-display, backing-scale transitions, full-screen Spaces, and recursive
capture remain explicit checks before Phase 5 is merged.
