# ADR 0001: Use OCR as the primary Discord text extractor

- Status: Accepted
- Date: 2026-08-02
- Issue: [#1](https://github.com/NI-yy/Kotoverlay/issues/1)

## Context

Kotoverlay first tested macOS Accessibility because semantic text and geometry
would be faster and more accurate than OCR. The Phase 1 `axprobe` successfully:

- received Accessibility permission without restarting its host application;
- found Discord by bundle identifier and selected its main window;
- read the window title and frame;
- enabled Electron's documented `AXManualAccessibility` attribute; and
- completed bounded scans well below 250 ms.

Before Discord was relaunched, its tree contained seven nested `AXGroup`
elements and no message text. After a complete Discord relaunch, it contained
eleven elements: the same empty groups plus window-control buttons. Foregrounding
Discord did not expose message descendants. No captured message text was written
to the test record.

## Decision

Use ScreenCaptureKit window capture and Vision text recognition as the primary
Discord content extractor. Retain Accessibility for permission-independent
application/window feasibility diagnostics and as a possible source of window
metadata, but do not depend on it for Discord message bodies.

The work originally numbered Phase 6 is promoted immediately after Phase 1 and
may proceed in parallel with the local Ollama translation spike. Existing phase
and issue numbers are retained to avoid rewriting project history.

## Consequences

- Kotoverlay must request Screen Recording permission before it can translate.
- Capture must be limited to the selected Discord window and never persisted by
  default.
- OCR needs change detection, region cropping, confidence filtering, and a
  capped scan rate to control CPU use on the reference 8 GB Mac.
- Text coordinates come from Vision observations and require normalization into
  macOS screen coordinates.
- Accessibility remains useful for Discord discovery and diagnostics, but OCR
  success is now the next extraction gate.
