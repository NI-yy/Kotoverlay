# Live pipeline verification guide

`pipelineprobe` connects the existing Discord-window OCR path to the local
translation provider without introducing a graphical UI. It is the manual
diagnostic for Phase 3; deterministic unit tests exercise the same core with
synthetic observations and a mock provider.

## Data flow

```text
Discord window capture (ScreenCaptureKit, memory only)
  -> changed-frame check
  -> Vision OCR and screen-space rectangles
  -> confidence, Discord UI, code-only, and English filtering
  -> stable message identity and duplicate removal
  -> memory / optional persistent cache lookup
  -> newest-visible-first bounded translation queue
  -> local Ollama provider
  -> ordered TranslationResult values
```

Every new changed snapshot supersedes in-flight work from the previous snapshot.
The provider receives cancellation through Swift tasks, so a quick scroll or
channel change does not leave old translations eligible for presentation.

## Usage

Start Discord and Ollama, then run one redacted pass:

```sh
swift run pipelineprobe --prompt
```

After Screen Recording permission is granted, continuous verification is:

```sh
swift run pipelineprobe --watch
swift run pipelineprobe --watch --iterations 10
```

The interval cannot be below 0.5 seconds. Unchanged captures skip Vision and the
translation pipeline. Use `--fast` for faster Vision recognition, `--model` and
`--timeout` for Ollama, and `--help` for all options.

Output contains observation counts, eligible/excluded counts, cache hits,
translation counts, cancellation state, and error categories. Source and
translated text are omitted unless `--show-content` is explicitly supplied.

## Identity, ordering, and caching

Message identity hashes a version, stable context identifier, normalized author
when available, normalized text, and duplicate occurrence. Geometry is excluded
so the same message remains stable while scrolling. Results are translated from
newest to oldest but returned in visible order for presentation.

The default cache is memory-only. `--cache PATH` explicitly enables a layered
memory and versioned JSON cache. Cache keys hash message identity, language pair,
provider/model identity, and prompt version; raw source text is not stored in
the key. The persistent value contains the translated text and timestamp, so
the selected cache file must still be treated as private. Version 1 cache files
are migrated to version 2 when opened.

## Privacy boundaries

- ScreenCaptureKit selects only the Discord window.
- Captured images remain in memory and are never written by the probe.
- Ollama remains fixed to `127.0.0.1` through `OllamaTranslationProvider`.
- Persistent caching is off by default.
- Structured diagnostics contain only counts and error categories.
- `--show-content` is an explicit local diagnostic and its terminal output must
  not be pasted into issues or committed.

## Verification

Automated tests cover English/UI/code filtering, stable ordering, exact OCR
duplicate removal, cache reuse, bounded concurrency, stale-work cancellation,
content-free diagnostics, layered cache behavior, and version 1 migration.

Reference M2 / 8 GB integration result on 2026-08-03:

- One Discord capture produced 19 OCR observations.
- 10 English candidates were selected and translated locally.
- The run completed with no provider or cache failure.
- In a two-capture watch run, the unchanged second frame skipped OCR and
  translation.

The probe currently uses a stable Discord window identifier as its context. A
later UI phase can enrich this with channel metadata when it has a reliable
source, without changing the cache and scheduler interfaces.
