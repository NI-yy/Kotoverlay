# Local translation CLI

`kotoverlay-cli` validates English-to-Japanese translation through a local
Ollama instance before OCR, caching, and the overlay UI are connected.

## Prerequisites

- Start the Ollama macOS application.
- Install `qwen3:1.7b` with `ollama pull qwen3:1.7b` if it is not already listed.
- Build from the repository with Xcode 26 or Swift 6.

The build, tests, and CI never start Ollama or download a model.

## Usage

```sh
swift run kotoverlay-cli --health
swift run kotoverlay-cli --list-models
swift run kotoverlay-cli "The Metal shader failed to compile lol"
printf 'Can Terminal.app do that?' | swift run kotoverlay-cli
```

Use `--model NAME` to select another installed model and `--timeout SECONDS` to
change the 30-second generation timeout. Translation is printed to standard
output; timing and deterministic error messages are printed to standard error.

## Behavior and privacy

- `TranslationProvider` keeps the translation engine replaceable.
- `OllamaTranslationProvider` calls only `http://127.0.0.1:11434`; other hosts,
  credentials, HTTPS endpoints, and redirects away from loopback are rejected.
- The provider verifies the configured model through `/api/tags` before using
  `/api/generate`.
- Ollama's newline-delimited JSON response is parsed incrementally. The provider
  buffers one short message, restores protected tokens, and then publishes the
  completed translation so placeholder fragments never appear in the UI.
- URLs, mentions, code-like expressions, slash-separated names, and selected
  graphics API names are replaced with placeholders and restored exactly.
- Source text, translation text, and HTTP bodies are not logged or persisted.

Timeout and task cancellation stop the HTTP stream. A missing server, missing
model, malformed JSON line, incomplete response, lost placeholder, and timeout
produce distinct errors.

## Reference measurement

Measured on the project's Apple M2 / 8 GB reference Mac with Ollama 0.32.5 and
the warmed `qwen3:1.7b` model on 2026-08-03:

| Input | Result | Time |
| --- | --- | ---: |
| `@nesnrve The Metal shader failed at commandBuffer.commit(); see https://developer.apple.com/metal/ lol` | `@nesnrve The Metal シェーダーがcommandBuffer.commit();で失敗しました。https://developer.apple.com/metal/を見て lol` | 1114.9 ms |
| `Honestly I usually use the default shell emulator on win/nux but here I needed something that can change the command key to alt lol` | `実際には、win/nux で通常使っているデフォルトのシェルエミュレーターを使用しているけど、ここではコマンドキーをALTに変更できるものが必要だったよ、笑` | 1239.2 ms |

The small model preserves the tested protected terms, but wording can still be
awkward and slang is not always translated consistently. Later phases should
cache unchanged messages and evaluate prompt/model alternatives without making
model download part of the application build.

## Automated verification

`swift test` uses an injected mock HTTP transport. It covers model discovery,
successful NDJSON parsing, non-loopback rejection, connection failure, missing
model, malformed and incomplete streams, timeout, cancellation, and protected
token restoration without requiring Ollama in CI.
