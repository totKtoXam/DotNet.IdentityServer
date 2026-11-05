#!/usr/bin/env bash
# Verifies that product code never modifies upstream (Open.IdentityServer) files.
#
# Baseline: the highest upstream release tag (plain semver, e.g. 3.1.3) merged into the
# checked revision. Rules:
#   1. Every file of the baseline is present and byte-identical (content and mode),
#      unless it is registered in product/UPSTREAM_PATCHES.md.
#   2. Every file that is not in the baseline lives in a product-owned location.
#   3. .claude/settings.json denies agent edits for every upstream top-level entry
#      and every upstream file under .github/.
#
# The check compares whole trees, so it works the same for feature PRs, upstream sync
# PRs and pushes to product/main. A squash-merged sync is detected because the tag is
# then no longer an ancestor and the baseline falls back to the previous release.
#
# Usage:
#   product/scripts/check-upstream-boundary.sh [<rev>]    check a commit (default: HEAD)
#   product/scripts/check-upstream-boundary.sh --staged   check the index (pre-commit hook)
#
# Environment:
#   UPSTREAM_TAG_NS  ref namespace holding upstream release tags (default: refs/tags).
#                    CI fetches upstream tags into refs/upstream-tags so that tags created
#                    in the fork can never become the baseline.

set -euo pipefail

registry_path=product/UPSTREAM_PATCHES.md
settings_path=.claude/settings.json
tag_ns=${UPSTREAM_TAG_NS:-refs/tags}
tag_ns=${tag_ns%/}

mode=commit
rev=HEAD
case "${1:-}" in
  -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --staged) mode=staged ;;
  '') ;;
  -*) echo "error: unknown option '$1'" >&2; exit 2 ;;
  *) rev=$1 ;;
esac

# Paths owned by the product. Keep in sync with product/README.md and CLAUDE.md.
is_product_owned() {
  case "$1" in
    product/*|CLAUDE.md|.claude/*|.github/workflows/product-*.yml) return 0 ;;
    *) return 1 ;;
  esac
}

cd "$(git rev-parse --show-toplevel)"

if [[ $(git rev-parse --is-shallow-repository) == true ]]; then
  echo "warning: shallow repository, the baseline tag may be detected incorrectly" >&2
fi

merged_args=()
if [[ $mode == staged ]]; then
  if [[ -n $(git ls-files --unmerged) ]]; then
    echo "error: the index has unresolved merge conflicts; resolve them first" >&2
    exit 1
  fi
  merged_args+=(--merged HEAD)
  # While a merge is in progress the index already contains the merged upstream tag.
  if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    merged_args+=(--merged MERGE_HEAD)
  fi
  label="index"
else
  commit=$(git rev-parse -q --verify "$rev^{commit}") || { echo "error: '$rev' is not a commit" >&2; exit 2; }
  merged_args+=(--merged "$commit")
  label="$rev"
fi

baseline=$(git -c versionsort.suffix=- for-each-ref "${merged_args[@]}" --sort=-v:refname --count=1 \
  --format='%(refname:strip=2)' "$tag_ns/[0-9]*.[0-9]*.[0-9]*")
if [[ -z $baseline ]]; then
  echo "error: no upstream release tag in $tag_ns is merged into $label." >&2
  echo "       Fetch upstream tags: git fetch upstream --tags" >&2
  exit 2
fi
baseline_ref="$tag_ns/$baseline"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Reads a file of the checked revision (or of the index) to stdout; empty if missing.
show_file() {
  if [[ $mode == staged ]]; then
    git show ":$1" 2>/dev/null || true
  else
    git show "$commit:$1" 2>/dev/null || true
  fi
}

git ls-tree -r --name-only "$baseline_ref" | sort -u > "$tmp/upstream"
if [[ $mode == staged ]]; then
  git ls-files --cached | sort -u > "$tmp/current"
  git diff --cached --no-ext-diff --no-textconv --no-renames --name-only "$baseline_ref" | sort -u > "$tmp/changed"
else
  git ls-tree -r --name-only "$commit" | sort -u > "$tmp/current"
  git diff --no-ext-diff --no-textconv --no-renames --name-only "$baseline_ref" "$commit" | sort -u > "$tmp/changed"
fi

# First backticked path in each table row of the registry.
show_file "$registry_path" | sed -n 's/^|[[:space:]]*`\([^`]*\)`.*/\1/p' | sort -u > "$tmp/registered"

failed=0
warnings=0

# Rule 1: upstream files are unchanged unless registered.
comm -12 "$tmp/changed" "$tmp/upstream" > "$tmp/touched"
comm -23 "$tmp/touched" "$tmp/registered" > "$tmp/unregistered"
if [[ -s $tmp/unregistered ]]; then
  failed=1
  echo "error: upstream files changed, deleted or re-moded without a registered patch:" >&2
  sed 's/^/  - /' "$tmp/unregistered" >&2
  echo "  Move the change into product/ or register it in $registry_path (see product/README.md)." >&2
  echo >&2
fi

# Rule 2: files that are not upstream live in product-owned locations.
: > "$tmp/foreign"
while IFS= read -r path; do
  is_product_owned "$path" || printf '%s\n' "$path" >> "$tmp/foreign"
done < <(comm -23 "$tmp/current" "$tmp/upstream")
if [[ -s $tmp/foreign ]]; then
  failed=1
  echo "error: files outside product-owned locations that do not exist in upstream $baseline:" >&2
  sed 's/^/  - /' "$tmp/foreign" >&2
  echo "  Product code belongs in product/ (allowed elsewhere: CLAUDE.md, .claude/, .github/workflows/product-*.yml)." >&2
  echo >&2
fi

# Rule 3: agent edit protection covers every upstream entry.
show_file "$settings_path" > "$tmp/settings"
: > "$tmp/missing_rules"
while IFS=$'\t' read -r meta name; do
  [[ $name == .github ]] && continue
  if [[ $meta == *" tree "* ]]; then
    rule="Edit(/$name/**)"
  else
    rule="Edit(/$name)"
  fi
  grep -qF "\"$rule\"" "$tmp/settings" || printf '%s\n' "$rule" >> "$tmp/missing_rules"
done < <(git ls-tree "$baseline_ref")
while IFS= read -r path; do
  rule="Edit(/$path)"
  grep -qF "\"$rule\"" "$tmp/settings" || printf '%s\n' "$rule" >> "$tmp/missing_rules"
done < <(git ls-tree -r --name-only "$baseline_ref" -- .github)
if [[ -s $tmp/missing_rules ]]; then
  failed=1
  echo "error: $settings_path does not deny agent edits for these upstream entries; add to permissions.deny:" >&2
  sed 's/.*/  "&",/' "$tmp/missing_rules" >&2
  echo >&2
fi

# Registry hygiene: stale entries and missing FORK-PATCH markers.
while IFS= read -r path; do
  if ! grep -qxF "$path" "$tmp/upstream"; then
    warnings=1
    echo "warning: $registry_path lists '$path', which is not an upstream file in $baseline" >&2
  elif ! grep -qxF "$path" "$tmp/changed"; then
    warnings=1
    echo "warning: $registry_path lists '$path', but it is identical to upstream $baseline; remove the entry" >&2
  elif grep -qxF "$path" "$tmp/current" && ! show_file "$path" | grep -q 'FORK-PATCH'; then
    warnings=1
    echo "warning: '$path' is patched but has no FORK-PATCH marker" >&2
  fi
done < "$tmp/registered"

echo "upstream baseline: $baseline ($baseline_ref)"
echo "checked:           $label"
echo "upstream files:    $(wc -l < "$tmp/upstream") ($(wc -l < "$tmp/touched") patched or changed)"
echo "registered:        $(wc -l < "$tmp/registered")"

if (( failed )); then
  echo "FAILED: upstream boundary violated" >&2
  exit 1
fi
if (( warnings )); then
  echo "ok: upstream boundary respected (with warnings)"
else
  echo "ok: upstream boundary respected"
fi
