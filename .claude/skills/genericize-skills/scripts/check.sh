#!/usr/bin/env bash
# Mechanical checks for one skill directory against the genericize-skills rubric.
# FAIL lines are hard failures (exit 1). REVIEW lines need a human or checker judgement.
set -u
dir="${1:?usage: check.sh <skill-dir>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
terms_file="$here/references/project-terms.txt"
skill="$dir/SKILL.md"
max_lines=250
failed=0

fail() { echo "FAIL   $*"; failed=1; }
review() { echo "REVIEW $*"; }

[ -f "$skill" ] || { fail "$skill does not exist"; exit 1; }

# Frontmatter: opening ---, name matching the folder, a description with a trigger.
[ "$(head -n 1 "$skill")" = "---" ] || fail "$skill: no frontmatter"
name="$(sed -n 's/^name: *//p' "$skill" | head -n 1)"
[ -n "$name" ] || fail "$skill: frontmatter has no name"
[ -z "$name" ] || [ "$name" = "$(basename "$dir")" ] || fail "$skill: name '$name' does not match folder '$(basename "$dir")'"
grep -q '^description: ' "$skill" || fail "$skill: frontmatter has no description"
grep -m1 '^description: ' "$skill" | grep -qi 'use when' || review "$skill: description has no 'Use when' trigger"

lines=$(wc -l < "$skill")
[ "$lines" -le "$max_lines" ] || fail "$skill: $lines lines (limit $max_lines); move detail to references/"
echo "INFO   $skill: $lines lines"

if grep -qi '^## Before you start' "$skill"; then
  sed -n '/^## Before you start/,/^## /p' "$skill" | grep -qiE 'win|take(s)? precedence|override' \
    || fail "$skill: '## Before you start' does not say the project's conventions win"
else
  fail "$skill: no '## Before you start' section"
fi
grep -qi '^## Checklist' "$skill" || review "$skill: no '## Checklist' section"
grep -nqi '^## Placeholders' "$skill" && fail "$skill: has a '## Placeholders' section"

# Every references/ file should be linked from SKILL.md.
if [ -d "$dir/references" ]; then
  for ref in "$dir"/references/*.md; do
    [ -e "$ref" ] || continue
    grep -qF "references/$(basename "$ref")" "$skill" || review "$ref is not linked from SKILL.md"
  done
fi

# Raw control bytes (NUL, ESC) make git treat the file as binary.
while IFS= read -r -d '' f; do
  n=$(tr -dc '\000\033' < "$f" | wc -c)
  [ "$n" -eq 0 ] || fail "$f: $n raw control byte(s)"
done < <(find "$dir" -type f -print0)

# Angle-bracket placeholders that are not HTML tags.
html='a|abbr|article|aside|b|body|br|button|code|dd|details|dialog|div|dl|dt|em|fieldset|footer|form|h[1-6]|head|header|hr|html|i|iframe|img|input|label|legend|li|link|main|meta|nav|ol|option|p|pre|script|section|select|slot|span|strong|style|summary|table|tbody|td|template|textarea|th|thead|title|tr|ul|video'
grep -rnoE '<[a-z][a-z0-9-]*>' "$dir" --include='*.md' \
  | grep -vE ":<($html)>$" \
  | while IFS= read -r hit; do review "placeholder? $hit"; done

# Known project-specific terms.
if [ -f "$terms_file" ]; then
  grep -v '^#' "$terms_file" | grep -v '^[[:space:]]*$' > "${TMPDIR:-/tmp}/genericize-terms.$$"
  grep -rniF -f "${TMPDIR:-/tmp}/genericize-terms.$$" "$dir" --include='*.md' \
    | while IFS= read -r hit; do review "project term? $hit"; done
  rm -f "${TMPDIR:-/tmp}/genericize-terms.$$"
fi

[ "$failed" -eq 0 ] && echo "RESULT pass (resolve REVIEW lines by judgement)" || echo "RESULT fail"
exit "$failed"
