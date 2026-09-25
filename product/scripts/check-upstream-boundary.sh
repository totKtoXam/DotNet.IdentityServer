#!/usr/bin/env bash
# Fails when a change touches files owned by upstream (Open.IdentityServer)
# that are not registered in product/UPSTREAM_PATCHES.md.
#
# Usage: product/scripts/check-upstream-boundary.sh <base-ref> [head-ref]
#   base-ref  branch the change will be merged into, e.g. origin/product/main
#   head-ref  tip of the change (default: HEAD)

set -euo pipefail

base=${1:?usage: check-upstream-boundary.sh <base-ref> [head-ref]}
head=${2:-HEAD}

repo_root=$(git rev-parse --show-toplevel)
registry="$repo_root/product/UPSTREAM_PATCHES.md"

# Upstream release tags are plain semver (2.0.0, 2.1.0-rc1).
# Product tags must use the product/v* prefix so they never match here.
upstream_tag=$(git describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*' "$head" 2>/dev/null) || {
  echo "error: no upstream release tag is reachable from $head; run 'git fetch --tags'" >&2
  exit 2
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git ls-tree -r --name-only "$upstream_tag" | sort -u > "$tmp/upstream"
git diff --no-renames --name-only "$base...$head" | sort -u > "$tmp/changed"

# First backticked path in each table row of the registry.
if [[ -f "$registry" ]]; then
  sed -n 's/^|[[:space:]]*`\([^`]*\)`.*/\1/p' "$registry" | sort -u > "$tmp/allowed"
else
  : > "$tmp/allowed"
fi

comm -12 "$tmp/changed" "$tmp/upstream" > "$tmp/touched"
comm -23 "$tmp/touched" "$tmp/allowed" > "$tmp/violations"

echo "upstream baseline: $upstream_tag"
echo "changed files:     $(wc -l < "$tmp/changed")"
echo "upstream touched:  $(wc -l < "$tmp/touched")"

if [[ -s "$tmp/violations" ]]; then
  echo
  echo "error: these upstream files were changed but are not registered in product/UPSTREAM_PATCHES.md:" >&2
  sed 's/^/  - /' "$tmp/violations" >&2
  echo >&2
  echo "Move the change into product/ or register the patch (see product/README.md)." >&2
  exit 1
fi

echo "ok: upstream boundary respected"
