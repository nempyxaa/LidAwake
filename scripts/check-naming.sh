#!/bin/bash
# Naming rule (v3 spec): "Lid Awake" in prose; lid-awake only inside code
# spans, fenced blocks, paths, and identifiers. "Keep awake" is the feature's
# proper name; "keep-awake", "staying awake", and "night mode" are banned.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

check_prose() {
  local f="$1"
  # Drop fenced code blocks, then inline code spans and markdown link targets;
  # what remains is prose.
  local stripped
  stripped="$(awk 'BEGIN{fence=0} /^(```|~~~)/{fence=!fence; next} !fence' "$f" \
    | sed -E 's/`[^`]*`//g; s/\]\([^)]*\)/]/g')"
  if grep -n "lid-awake" <<<"$stripped" >/dev/null; then
    echo "NAMING: lowercase 'lid-awake' in prose of $f (use \"Lid Awake\" or a code span):"
    grep -n "lid-awake" <<<"$stripped" | head -5
    fail=1
  fi
  local banned
  for banned in "keep-awake" "staying awake" "night mode"; do
    if grep -in "$banned" <<<"$stripped" >/dev/null; then
      echo "NAMING: banned term '$banned' in $f:"
      grep -in "$banned" <<<"$stripped" | head -5
      fail=1
    fi
  done
}

for f in README.md native/README.md docs/*.md; do
  [ -f "$f" ] || continue
  check_prose "$f"
done

# User-facing strings in the sources must not carry banned terms either.
if grep -rn --include='*.swift' -e 'keep-awake' -e 'staying awake' -e 'night mode' native/Sources; then
  echo "NAMING: banned term in Swift sources"
  fail=1
fi

if [ "$fail" = 0 ]; then echo "naming check passed"; fi
exit $fail
