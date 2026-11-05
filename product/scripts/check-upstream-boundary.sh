#!/usr/bin/env bash
# Verifies that product code never modifies upstream (Open.IdentityServer) files.
#
# Baseline: the upstream release recorded in product/UPSTREAM_BASELINE (tag and commit),
# written by product/scripts/sync-upstream.sh. Rules:
#   0. The baseline commit is an ancestor of the checked revision (a squash-merged sync
#      fails here), no newer upstream release is merged without updating the baseline
#      (a hand-made merge or a reverted sync fails here), and the commit matches its tag
#      wherever that tag is available.
#   1. Every file of the baseline is present and byte-identical (content and mode),
#      unless it is registered in product/UPSTREAM_PATCHES.md with a FORK-PATCH marker.
#   2. Every file that is not in the baseline lives in a product-owned location.
#   3. .claude/settings.json denies agent edits of every upstream top-level entry,
#      every upstream file under .github/ and the guard files themselves.
#
# Usage:
#   product/scripts/check-upstream-boundary.sh [<rev>]    check a commit (default: HEAD)
#   product/scripts/check-upstream-boundary.sh --staged   check the index (pre-commit hook)
#
# Environment:
#   UPSTREAM_TAG_NS  ref namespace holding upstream release tags (default: refs/tags).
#                    CI fetches upstream tags into refs/upstream-tags.

set -euo pipefail
export LC_ALL=C

baseline_path=product/UPSTREAM_BASELINE
registry_path=product/UPSTREAM_PATCHES.md
settings_path=.claude/settings.json
tag_ns=${UPSTREAM_TAG_NS:-refs/tags}
tag_ns=${tag_ns%/}

# Agent edit protection that must exist besides the upstream entries.
guard_rules=(
  "Edit(/.claude/settings.json)"
  "Edit(/product/scripts/**)"
  "Edit(/product/UPSTREAM_BASELINE)"
  "Edit(/product/UPSTREAM_PATCHES.md)"
  "Edit(/.github/workflows/product-*.yml)"
)

# Paths owned by the product. Keep in sync with product/README.md and CLAUDE.md.
is_product_owned() {
  case "$1" in
    product/*|CLAUDE.md|.claude/*|.github/workflows/product-*.yml) return 0 ;;
    *) return 1 ;;
  esac
}

# File types that can carry a FORK-PATCH comment.
can_carry_marker() {
  case "$1" in
    *.cs|*.csproj|*.props|*.targets|*.xml|*.config|*.cshtml|*.razor|*.js|*.ts|*.css|*.scss|\
    *.html|*.sh|*.ps1|*.cmd|*.bat|*.yml|*.yaml|*.md|*.MD|*.rst|*.py|*.sql|*.txt) return 0 ;;
    *) return 1 ;;
  esac
}

git() { command git -c core.quotePath=false "$@"; }

mode=commit
rev=HEAD
case "${1:-}" in
  -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --staged) mode=staged ;;
  '') ;;
  -*) echo "error: unknown option '$1'" >&2; exit 2 ;;
  *) rev=$1 ;;
esac
if (( $# > 1 )); then
  echo "error: expected at most one argument; run without arguments to check HEAD" >&2
  exit 2
fi

cd "$(git rev-parse --show-toplevel)"

shallow=$(git rev-parse --is-shallow-repository)
if [[ $shallow == true ]]; then
  echo "warning: shallow repository; if the check fails, run: git fetch --unshallow origin" >&2
fi

tips=()
if [[ $mode == staged ]]; then
  if [[ -n $(git ls-files --unmerged) ]]; then
    echo "error: the index has unresolved merge conflicts; resolve them first" >&2
    exit 1
  fi
  tips+=(HEAD)
  # While a merge is in progress the index already contains the merged upstream release.
  if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    tips+=("$(git rev-parse MERGE_HEAD)")
  fi
  label="index"
else
  commit=$(git rev-parse -q --verify "$rev^{commit}") || { echo "error: '$rev' is not a commit" >&2; exit 2; }
  tips+=("$commit")
  label="$rev"
fi

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

failed=0
warnings=0
fail() { failed=1; printf 'error: %s\n' "$*" >&2; }
warn() { warnings=1; printf 'warning: %s\n' "$*" >&2; }

# Rule 0: the recorded baseline is valid for this revision.
show_file "$baseline_path" > "$tmp/baseline"
base_tag=$(sed -n 's/^tag=//p' "$tmp/baseline" | head -n 1)
base_commit=$(sed -n 's/^commit=//p' "$tmp/baseline" | head -n 1)
if [[ ! $base_tag =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ || ! $base_commit =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: $baseline_path is missing or malformed in $label (expected tag=X.Y.Z and commit=<sha>)" >&2
  exit 1
fi
if ! git cat-file -e "$base_commit^{commit}" 2>/dev/null; then
  echo "error: baseline commit $base_commit ($base_tag) is not in this clone; run: git fetch --unshallow origin" >&2
  exit 1
fi

reachable=0
for tip in "${tips[@]}"; do
  if git merge-base --is-ancestor "$base_commit" "$tip"; then reachable=1; fi
done
if (( ! reachable )); then
  fail "upstream $base_tag ($base_commit) is not in the history of $label. A sync PR was squash-merged or rebased,
       or $baseline_path was edited by hand. Merge the original sync branch with 'Create a merge commit'."
fi

tag_commit=$(git rev-parse -q --verify "$tag_ns/$base_tag^{commit}" || true)
if [[ -n $tag_commit && $tag_commit != "$base_commit" ]]; then
  fail "$baseline_path says $base_tag is $base_commit, but $tag_ns/$base_tag is $tag_commit"
fi

merged_args=()
for tip in "${tips[@]}"; do merged_args+=(--merged "$tip"); done
git for-each-ref "${merged_args[@]}" --no-merged "$base_commit" --format='%(refname)' \
  "$tag_ns/[0-9]*.[0-9]*.[0-9]*" > "$tmp/newer"
if [[ -s $tmp/newer ]]; then
  fail "release tags merged after the baseline $base_tag: $(sed "s|^$tag_ns/||" "$tmp/newer" | tr '\n' ' ')
       Causes: an upstream merge without product/scripts/sync-upstream.sh, a reverted sync,
       or a numeric tag created in the fork (numeric tags belong to upstream)."
fi

# File lists.
git ls-tree -r --name-only "$base_commit" | sort -u > "$tmp/upstream"
if [[ $mode == staged ]]; then
  git ls-files --cached | sort -u > "$tmp/current"
  git diff --cached --no-ext-diff --no-textconv --no-renames --name-only "$base_commit" | sort -u > "$tmp/changed"
else
  git ls-tree -r --name-only "$commit" | sort -u > "$tmp/current"
  git diff --no-ext-diff --no-textconv --no-renames --name-only "$base_commit" "$commit" | sort -u > "$tmp/changed"
fi

# Registry rows: the table that starts with the "| Файл |" header, first backticked path per row.
show_file "$registry_path" | tr -d '\r' > "$tmp/registry"
awk '
  /^\|[[:space:]]*Файл[[:space:]]*\|/ { in_table = 1; next }
  in_table && /^\|[-:| ]+$/          { next }
  in_table && /^\|/                  { print; next }
  in_table                           { exit }
' "$tmp/registry" | sed -n 's/^|[[:space:]]*`\([^`]*\)`.*/\1/p' | sort -u > "$tmp/registered"
grep -c '^|[[:space:]]*`' "$tmp/registry" > "$tmp/all_rows" || true
if (( $(cat "$tmp/all_rows") != $(wc -l < "$tmp/registered") )); then
  fail "$registry_path has patch rows outside its table; keep all rows in the single table"
fi

# Rule 1: upstream files are unchanged unless registered.
comm -12 "$tmp/changed" "$tmp/upstream" > "$tmp/touched"
comm -23 "$tmp/touched" "$tmp/registered" > "$tmp/unregistered"
if [[ -s $tmp/unregistered ]]; then
  fail "upstream files changed, deleted or re-moded without a registered patch:
$(sed 's/^/  - /' "$tmp/unregistered")
  Move the change into product/. A change that cannot be made outside upstream needs a human-made,
  registered patch (see product/README.md)."
fi

# Rule 2: files that are not upstream live in product-owned locations.
: > "$tmp/foreign"
while IFS= read -r path; do
  is_product_owned "$path" || printf '%s\n' "$path" >> "$tmp/foreign"
done < <(comm -23 "$tmp/current" "$tmp/upstream")
if [[ -s $tmp/foreign ]]; then
  fail "files outside product-owned locations that do not exist in upstream $base_tag:
$(sed 's/^/  - /' "$tmp/foreign")
  Product code belongs in product/ (allowed elsewhere: CLAUDE.md, .claude/, .github/workflows/product-*.yml)."
fi

# Rule 3: agent edit protection covers every upstream entry and the guard itself.
{
  while IFS=$'\t' read -r meta name; do
    [[ $name == .github ]] && continue
    if [[ $meta == *" tree "* ]]; then echo "Edit(/$name/**)"; else echo "Edit(/$name)"; fi
  done < <(git ls-tree "$base_commit")
  git ls-tree -r --name-only "$base_commit" -- .github | sed 's|.*|Edit(/&)|'
  printf '%s\n' "${guard_rules[@]}"
} | sort -u > "$tmp/required_rules"

show_file "$settings_path" > "$tmp/settings"
if command -v jq >/dev/null 2>&1; then
  if ! jq -er '.permissions.deny | if type == "array" then .[] else error("not an array") end' \
      "$tmp/settings" > "$tmp/deny" 2>/dev/null; then
    fail "$settings_path is missing, is not valid JSON or has no permissions.deny array"
    : > "$tmp/deny"
  fi
  sort -u -o "$tmp/deny" "$tmp/deny"
  comm -23 "$tmp/required_rules" "$tmp/deny" > "$tmp/missing_rules"
else
  warn "jq not found; $settings_path is checked by text search only (CI checks it exactly)"
  : > "$tmp/missing_rules"
  while IFS= read -r rule; do
    grep -qF "\"$rule\"" "$tmp/settings" || printf '%s\n' "$rule" >> "$tmp/missing_rules"
  done < "$tmp/required_rules"
fi
if [[ -s $tmp/missing_rules ]]; then
  fail "$settings_path must deny agent edits of these paths; add to permissions.deny (a human edits this file):
$(sed 's/.*/  "&",/' "$tmp/missing_rules")"
fi

# Registry hygiene.
while IFS= read -r path; do
  if ! grep -qxF -- "$path" "$tmp/upstream"; then
    warn "$registry_path lists '$path', which is not an upstream file in $base_tag"
  elif ! grep -qxF -- "$path" "$tmp/current"; then
    fail "registered upstream file '$path' was deleted; deleting upstream files is not allowed"
  elif ! grep -qxF -- "$path" "$tmp/changed"; then
    warn "$registry_path lists '$path', but it is identical to upstream $base_tag; remove the entry"
  elif can_carry_marker "$path" && ! show_file "$path" | grep -q 'FORK-PATCH'; then
    fail "patched upstream file '$path' has no FORK-PATCH comment"
  fi
done < "$tmp/registered"

echo "upstream baseline: $base_tag ($base_commit)"
echo "checked:           $label"
echo "upstream files:    $(wc -l < "$tmp/upstream") ($(wc -l < "$tmp/touched") patched)"
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
