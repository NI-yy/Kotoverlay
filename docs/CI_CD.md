# CI/CD plan

## Continuous integration

The repository uses GitHub Actions on the `macos-26` Apple Silicon runner. The
workflow has explicit `contents: read` permission and runs for pushes to `main`
and for pull requests.

`Scripts/ci.sh` is the single local and hosted entry point. It evolves with the
repository:

1. Documentation-only stage: validate required repository files and Git
   whitespace.
2. Swift Package stage: resolve, build, and test the package.
3. App stage: build the shared macOS scheme with code signing disabled.
4. Fixture stage: run synthetic extraction and mocked Ollama integration tests.

CI must never install Ollama, download a model, request macOS privacy permission,
or access real Discord content.

## Test layers

- Unit tests: normalization, identity, filtering, prompts, cache, scheduler.
- Contract tests: mock Ollama streaming and error responses.
- Fixture tests: sanitized Accessibility/OCR snapshots committed as test data.
- Local integration tests: real Discord, Accessibility permissions, Ollama, and
  overlays; never required in hosted CI.
- Manual release checks: Spaces, multiple displays, Retina scaling, permissions,
  relaunch, and clean installation.

## Continuous delivery

Release automation is intentionally deferred until the app target exists.

Planned flow:

1. A semantic version tag triggers a release workflow.
2. The workflow repeats the complete CI suite.
3. It archives the app and produces an unsigned dry-run artifact.
4. After Developer ID enrollment, a protected `release` environment provides
   short-lived access to signing and notarization credentials.
5. The workflow signs, notarizes, staples, packages, and verifies the app.
6. GitHub Release receives the package, SHA-256 checksum, and generated notes.

Pull-request workflows never receive signing secrets. Release jobs use the
smallest possible `GITHUB_TOKEN` permissions; `contents: write` is granted only
to the final publishing job.

## Branch and release policy

- `main` must remain buildable.
- Feature work uses short-lived branches and pull requests.
- Required status check: `CI / validate-and-test`.
- Releases use annotated `vMAJOR.MINOR.PATCH` tags.
- Breaking cache or configuration changes require migration tests.
- Model weights are never attached to source releases.
