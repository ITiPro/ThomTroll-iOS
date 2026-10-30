#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc Shared/Library.swift Tests/main.swift -o "$test_dir/model-tests"
"$test_dir/model-tests"
