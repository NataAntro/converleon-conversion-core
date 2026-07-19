#!/usr/bin/env bash

set -euo pipefail

swift test --enable-code-coverage

build_path="$(swift build --show-bin-path)"
test_binary="$build_path/converleon-conversion-corePackageTests.xctest/Contents/MacOS/converleon-conversion-corePackageTests"
profile="$build_path/codecov/default.profdata"

report="$(
  xcrun llvm-cov report "$test_binary" \
    -instr-profile "$profile" \
    -ignore-filename-regex='Tests|ConversionDemo|runner.swift'
)"
printf '%s\n' "$report"

line_coverage="$(printf '%s\n' "$report" | awk '/^TOTAL/ { gsub("%", "", $10); print $10 }')"
if [[ -z "$line_coverage" ]]; then
  echo "Не удалось определить покрытие строк" >&2
  exit 1
fi

awk -v coverage="$line_coverage" 'BEGIN { exit !(coverage + 0 >= 85) }'
