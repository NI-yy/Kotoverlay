# OCRProbe verification guide

`ocrprobe` is the privacy-safe Phase 6 diagnostic for the primary Discord text
extraction path. It selects a shareable window owned by `com.hnc.Discord`,
captures one in-memory image with ScreenCaptureKit, and recognizes text and
geometry with Vision.

It never captures the entire desktop, writes an image to disk, or prints
recognized text unless `--show-text` is explicitly supplied.

By default, Vision recognizes only the probable Discord message region. The
server/channel sidebar, top toolbar, and message composer are excluded. Use
`--whole-window` only when diagnosing that crop.

## Automated verification

```sh
./Scripts/ci.sh
swift run ocrprobe --help
```

CI tests coordinate conversion and recognizes text drawn into a synthetic image.
It does not request Screen Recording permission or capture the CI desktop.

## Grant Screen Recording permission

1. Start Discord and display a channel with visible messages.
2. Run `swift run ocrprobe --prompt`.
3. In **System Settings → Privacy & Security → Screen & System Audio Recording**,
   enable the host application or executable shown by macOS.
4. If macOS requests a restart, restart that host application and run the command
   again without `--prompt`.

The default output contains only text lengths, confidence values, timings, and
screen-space rectangles. Use `--show-text` only for a local diagnostic whose
terminal output will not be shared.

## Initial exit gate

- Only the selected Discord window is captured.
- Visible messages produce text observations and usable rectangles.
- The captured image is not persisted.
- Permission denial produces a clear recovery error.
- Synthetic OCR and coordinate tests pass in CI.

Continuous capture, frame-change detection, and the two-scans-per-second limit
can be tested without printing text:

```sh
swift run ocrprobe --watch
```

The interval cannot be set below 0.5 seconds. A small grayscale signature is
kept in memory, and unchanged frames skip Vision OCR. `--iterations N` provides
a bounded watch run for diagnostics and performance measurements.

## Reference-machine observation (2026-08-03)

- macOS 26, Apple M2 / 8 GB, Discord window `1470 × 858` points.
- Discord-window-only capture succeeded without writing an image to disk.
- The default message crop recognized 19 redacted text regions with screen
  coordinates.
- Representative timing: 147.2 ms capture and 420.9 ms accurate OCR.
- A bounded two-capture watch run skipped OCR on the unchanged second frame.
- Synthetic OCR, frame-change, and coordinate tests require no
  Screen Recording permission in CI.
