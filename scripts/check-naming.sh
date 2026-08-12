#!/bin/bash
# Naming law (v3 spec, FINAL): the app is "LidAwake" (CamelCase) on every
# surface; "lidawake" (no hyphen) where lowercase is forced. The retired
# spaced and hyphenated forms are banned in README/docs prose (code spans,
# fenced blocks, and historical URLs excepted), the sunset working title is
# banned everywhere, and "Keep awake" is the feature's proper name — no
# "keep-awake", "staying awake", or "night mode" anywhere.
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
  local banned
  for banned in "Lid Awake" "lid awake" "lid-awake" "keep-awake" "lid-governor" "staying awake" "night mode"; do
    if grep -in -- "$banned" <<<"$stripped" >/dev/null; then
      echo "NAMING: banned form '$banned' in prose of $f (the app is \"LidAwake\"):"
      grep -in -- "$banned" <<<"$stripped" | head -5
      fail=1
    fi
  done
}

for f in README.md native/README.md docs/*.md; do
  [ -f "$f" ] || continue
  check_prose "$f"
done

# Sources must not carry the retired name forms, the sunset working title, or
# the banned feature terms. (The hyphenated lowercase form is NOT banned here:
# migration code must keep enumerating the old identifiers and paths it
# removes. Tests hold the banned literals on purpose — StringRuleTests sweeps
# every canonical string for them — so they are exempt from this grep.)
if grep -rn --include='*.swift' -e 'Lid Awake' -e 'lid awake' -e 'keep-awake' \
    -e 'lid-governor' -e 'staying awake' -e 'night mode' native/Sources; then
  echo "NAMING: banned term in Swift sources"
  fail=1
fi

if [ "$fail" = 0 ]; then echo "naming check passed"; fi
exit $fail
