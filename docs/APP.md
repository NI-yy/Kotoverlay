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
- **Ollama / qwen3:1.7b** — required and checked through loopback only.
- **Discord** — required to start; a visible desktop window must exist.
- **Accessibility** — optional and retained for diagnostics, not message text.

Available controls are Start, Pause, Retry, Clear Cache, Copy Diagnostics,
Settings, and Quit. Closing the companion panel pauses capture and translation.
Retry refreshes readiness and resumes when all required services are available.

## Companion panel behavior

While running, Kotoverlay captures at a maximum of twice per second. Unchanged
frames skip OCR. Changed frames supersede older translation work, so channel
switches and scrolling cannot publish stale results.

Translations are published progressively, newest visible text first. The panel
does not wait for every visible message to finish before showing the first
result. On the reference Apple-silicon Mac with `qwen3:1.7b`, manual verification
reduced time to first translation from about five seconds to under one second.
Total completion time still depends on the number and length of visible messages.

The non-activating utility panel:

- follows the Discord window's current screen-space frame;
- prefers the right side, falls back to the left, and clamps to the visible
  screen area;
- moves without activating Kotoverlay or intercepting input inside Discord;
- hides while Discord is absent, minimized, or not shareable;
- returns after Discord becomes visible or relaunches;
- can appear in full-screen and Space transitions;
- presents original and Japanese text together.

The Phase 5 in-place overlay will add click-through text directly over Discord.
This companion panel intentionally remains a separate window first.

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

Automated tests cover panel coordinate conversion and placement, plus the core
filtering, progressive delivery, ordering, cancellation, bounded concurrency,
and cache behavior. The initial reference-screen check reduced 49 raw candidates
to 19 after removing the dense Discord member column; later filtering also
removes common author, role, mention-only, reply-header, and timestamp regions.
