# Contributing to Kotoverlay

## Development principles

1. Keep extraction, translation, and presentation behind separate interfaces.
2. Add a deterministic test before fixing a parsing, caching, or concurrency bug.
3. Never require a network service in unit tests.
4. Treat captured text as sensitive and avoid persistent logging by default.
5. Keep model files, captures, credentials, and signing material out of Git.

## Workflow

1. Pick one roadmap issue with all dependencies complete.
2. Create a short-lived branch from `main`.
3. Add or update tests and documentation with the implementation.
4. Run `./Scripts/ci.sh` locally.
5. Open a pull request using the repository template.

## Commit style

Use a short imperative subject with an optional scope, for example:

```text
feat(accessibility): extract visible Discord text
test(translation): cover Ollama cancellation
docs: define OCR fallback exit criteria
```

## Privacy in reports

Use synthetic Discord messages in tests and issue reports. Redact server names,
user names, avatars, channel names, tokens, file paths, and any other personal or
community information.
