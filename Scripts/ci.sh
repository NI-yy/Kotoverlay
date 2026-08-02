#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

required_files=(
  README.md
  LICENSE
  CONTRIBUTING.md
  docs/IMPLEMENTATION_PLAN.md
  docs/ARCHITECTURE.md
  docs/CI_CD.md
)

for required_file in "${required_files[@]}"; do
  if [[ ! -s "$required_file" ]]; then
    echo "Missing or empty required file: $required_file" >&2
    exit 1
  fi
done

git diff --check

if [[ -f Package.swift ]]; then
  swift package resolve
  swift build --build-tests
  swift test
else
  echo "Package.swift not present yet; skipping Swift package checks."
fi

if [[ -d Kotoverlay.xcodeproj ]]; then
  xcodebuild \
    -project Kotoverlay.xcodeproj \
    -scheme Kotoverlay \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "Kotoverlay.xcodeproj not present yet; skipping app build."
fi

echo "CI checks passed."
