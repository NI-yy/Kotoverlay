# Kotoverlay

Kotoverlay is an open-source macOS utility that translates visible English text
from Discord into Japanese with a local LLM and presents the result beside, and
eventually on top of, the source content.

The project is privacy-first: OCR and translation run on the Mac, and the first
translation provider is a local Ollama instance bound to `127.0.0.1`.

> [!NOTE]
> Kotoverlay is in the command-line validation stage. There is no downloadable
> application yet, but OCR and local-translation diagnostics are available.

## Product goals

- Detect Discord automatically; do not require repeated region selection.
- Translate only newly visible English messages and cache previous results.
- Preserve code, URLs, user names, and graphics-programming terminology.
- Keep captured text and translations on the local Mac.
- Build the core as reusable Swift code and validate it from a CLI before adding
  the full overlay UI.

## Planned architecture

```text
Discord
  -> window detection
  -> ScreenCaptureKit + Vision OCR
  -> message normalization and deduplication
  -> local Ollama translation provider
  -> translation cache
  -> CLI / companion panel / in-place overlay
```

The implementation will use Swift, Swift Package Manager, AppKit, SwiftUI,
ApplicationServices, Vision, and ScreenCaptureKit.

## Roadmap

1. Complete the Accessibility feasibility test and record the OCR decision.
2. Capture only the Discord window and recognize visible text with Vision OCR.
3. Connect a small Swift CLI to `qwen3:1.7b` through Ollama.
4. Combine extraction, translation, cancellation, and caching in
   `KotoverlayCore`.
5. Add a Discord-following translation panel.
6. Add click-through, in-place overlays.
7. Harden performance, privacy, permissions, and failure recovery.
8. Package and release the app.

Detailed exit criteria and dependencies are in
[docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md). See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries and
[docs/CI_CD.md](docs/CI_CD.md) for automation and release policy.

## Development requirements

- macOS 15 or later
- Xcode 26 or later
- Swift 6
- Ollama with `qwen3:1.7b` for local integration testing

No model is downloaded or started by the build. CI uses mocks and does not send
captured content to an external service.

## AXProbe quick start

Build and test:

```sh
swift build
swift test
```

Ask macOS for Accessibility permission and scan Discord once:

```sh
swift run axprobe --prompt
```

After granting permission in **System Settings → Privacy & Security →
Accessibility**, run the command again. To keep checking while granting the
permission or interacting with Discord:

```sh
swift run axprobe --watch
```

The command prints visible text because it is an explicit diagnostic action.
Kotoverlay does not persist the output. See all safety bounds and options with
`swift run axprobe --help`. The complete privacy notes and manual test matrix are
in [docs/AXPROBE.md](docs/AXPROBE.md).

The promoted OCR path has a one-shot Discord-window diagnostic:

```sh
swift run ocrprobe --prompt
```

Recognized text is redacted by default, and the captured image is never written
to disk. See [docs/OCRPROBE.md](docs/OCRPROBE.md) for the permission and test
procedure.

Check the local Ollama service and translate synthetic text:

```sh
swift run kotoverlay-cli --health
swift run kotoverlay-cli --list-models
swift run kotoverlay-cli "The Metal shader failed to compile lol"
```

The CLI accepts only the loopback Ollama endpoint and never downloads a model.
See [docs/TRANSLATION_CLI.md](docs/TRANSLATION_CLI.md) for usage, privacy
boundaries, failure behavior, and measured performance.

## Current development environment

The reference development machine is an Apple M2 Mac with 8 GB RAM. The default
model and performance targets are intentionally conservative for that hardware.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please do
not include Discord messages, screenshots, model files, signing certificates, or
other personal data in commits or bug reports.

## License

Kotoverlay is available under the [MIT License](LICENSE).
