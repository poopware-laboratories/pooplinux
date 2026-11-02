#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause
#
# Checks the repository's documentation contract:
#   1. Required top-level files exist.
#   2. Every relative link in tracked Markdown files points at an existing file.
#
# Anchors are not checked here. Heading anchors are verified in review.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

required=(
  README.md
  LICENSE
  ARCHITECTURE.md
  AGENTS.md
  CLAUDE.md
  CONTRIBUTING.md
  SECURITY.md
  CODE_OF_CONDUCT.md
  MAINTAINERS.md
  CHANGELOG.md
  .gitignore
  .github/PULL_REQUEST_TEMPLATE.md
)

for f in "${required[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "missing required file: $f"
    fail=1
  fi
done

while IFS= read -r file; do
  dir=$(dirname "$file")
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -z "$target" ]] && continue
    case "$target" in
      http:*|https:*|mailto:*) continue ;;
    esac
    if [[ ! -e "$dir/$target" ]]; then
      echo "$file: broken link -> $link"
      fail=1
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^(#|https?:|mailto:)' || true)
done < <(git ls-files '*.md')

if [[ $fail -ne 0 ]]; then
  echo "docs check failed"
  exit 1
fi

echo "docs check passed"
