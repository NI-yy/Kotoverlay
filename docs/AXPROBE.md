# AXProbe verification guide

`axprobe` is the Phase 1 diagnostic for deciding whether Discord's Accessibility
tree exposes enough message text and geometry to remain the primary extractor.
It does not translate, capture screenshots, or persist its output.

Discord is an Electron application. During each scan, `axprobe` sets Electron's
documented `AXManualAccessibility` attribute so Chromium exposes its web-content
accessibility tree to third-party assistive software. See Electron's official
[Accessibility guide](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md#within-third-party-software).

## Build verification

```sh
./Scripts/ci.sh
swift run axprobe --help
```

CI verifies deterministic element identifiers and clamps unsafe traversal
bounds. It does not need Accessibility permission or a running Discord process.

## Grant Accessibility permission

1. Start Discord and display a channel containing ordinary text messages.
2. Run `swift run axprobe --prompt --max-depth 0`.
3. Open **System Settings → Privacy & Security → Accessibility** if macOS does
   not open it automatically.
4. Enable the terminal or executable shown by macOS.
5. Run `swift run axprobe --max-depth 0` again to verify the permission without
   printing message descendants.

The system prompt is shown only with `--prompt`. `--watch` is useful when the
permission is changed while the diagnostic remains open.

## Discord feasibility scan

The normal scan deliberately prints text, roles, frames, and synthetic IDs to
the terminal. Do not paste real community messages into an issue or commit them.

```sh
swift run axprobe
```

Use `swift run axprobe --redact-text` when validating roles, geometry, and
timings without writing captured text to the terminal.
Add `--all-elements` when diagnosing where a tree stops exposing descendants.

The first summary line reports the element count, elapsed time, and whether the
scan stopped at its timeout or element limit. Use `swift run axprobe --help` to
adjust those bounds during investigation.

## Manual matrix

Record only counts, timings, and pass/fail notes—never captured message text.

| Scenario | Expected result | Status |
| --- | --- | --- |
| Discord absent | Clear `application not running` error | Passed with synthetic bundle ID |
| Permission denied | Clear permission error; no repeated prompt | Passed |
| Permission granted without app restart | Next scan succeeds | Passed |
| Discord relaunch | Web-content tree becomes available | Failed: no message descendants |
| Channel switch | Visible message text and frames update | Not applicable |
| Scroll | Visible set updates without hanging Discord | Not applicable |
| Resize | Frames track the resized window | Deferred to window-capture spike |
| Minimize/restore | Safe error or empty result, then recovery | Deferred to window-capture spike |
| Multiple Discord windows | Focused/main window is selected | Deferred to window-capture spike |

## Decision gate

Accessibility remains the primary extractor when visible message bodies have
usable screen-space frames and a scan is reliably below 250 ms on the reference
Mac. Otherwise, record the missing roles/attributes and promote the Phase 6 OCR
path. Exact overlay behavior is intentionally outside this phase.

## Reference-machine observation (2026-08-02)

- macOS 26, Apple M2 / 8 GB, Discord PID discovered successfully.
- Accessibility permission became active without restarting ChatGPT/Codex.
- Window-only scan: one element in 3.0 ms with a valid 1920 × 985 frame.
- Full redacted scan after `AXManualAccessibility`: seven nested `AXGroup`
  elements in 3.2 ms; no message text was exposed.
- Bringing Discord to the foreground did not change the result.

After a complete Discord relaunch, the scan returned eleven elements in 23.8 ms:
the same nested groups plus the three window-control buttons. It still exposed
no message text. Phase 1 therefore concludes that OCR must be the primary
Discord content extractor. The rationale and consequences are recorded in
[ADR 0001](decisions/0001-use-ocr-for-discord-content.md).
