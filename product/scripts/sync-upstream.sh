#!/usr/bin/env bash
# Prepares a branch that merges an upstream release tag into product/main.
#
# Usage: product/scripts/sync-upstream.sh <upstream-tag>
#   e.g. product/scripts/sync-upstream.sh 3.1.3
#
# The result is a local branch sync/upstream-<tag> with a merge commit. Push it and open
# a PR into product/main that is merged with "Create a merge commit" (never squash or
# rebase). Upstream tags are not pushed to origin: CI fetches them from upstream itself.

set -euo pipefail

upstream_url=https://github.com/RockSolidKnowledge/Open.IdentityServer.git
tag=${1:?usage: sync-upstream.sh <upstream-tag>}
branch="sync/upstream-$tag"
base=origin/product/main

die() { echo "error: $*" >&2; exit 1; }

[[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
  || die "'$tag' is not an upstream release tag (plain semver, e.g. 3.1.3)"

cd "$(git rev-parse --show-toplevel)"

[[ -z $(git status --porcelain) ]] || die "working tree is not clean"
! git show-ref --verify --quiet "refs/heads/$branch" || die "branch $branch already exists"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$upstream_url"
fi

git fetch upstream --tags \
  || die "fetching upstream tags failed. If git reported 'would clobber existing tag', a local numeric tag
       differs from upstream: numeric tags belong to upstream, delete the local one and retry."
git ls-remote --exit-code --tags upstream "refs/tags/$tag" >/dev/null \
  || die "tag $tag does not exist in upstream"
git fetch origin product/main

if git merge-base --is-ancestor "refs/tags/$tag" "$base"; then
  echo "product/main already contains $tag, nothing to do"
  exit 0
fi

current=$(git -c versionsort.suffix=- for-each-ref --merged "$base" --sort=-v:refname --count=1 \
  --format='%(refname:strip=2)' 'refs/tags/[0-9]*.[0-9]*.[0-9]*')
if [[ -n $current ]]; then
  newest=$(git -c versionsort.suffix=- tag --list --sort=-v:refname "$tag" "$current" | sed -n 1p)
  [[ $newest == "$tag" ]] || die "$tag is older than the current baseline $current of product/main"
fi

git switch -c "$branch" "$base"

if ! git merge --no-ff --no-edit -m "Merge upstream $tag into product/main" "refs/tags/$tag"; then
  echo
  echo "Merge conflicts in:"
  git diff --name-only --diff-filter=U | sed 's/^/  - /'
  echo
  echo "Resolve them: take the upstream version and re-apply the FORK-PATCH changes listed in"
  echo "product/UPSTREAM_PATCHES.md (drop entries that upstream made unnecessary). Then:"
  echo "  git add <files> && git commit"
  echo "  product/scripts/check-upstream-boundary.sh"
  exit 1
fi

echo
if ! product/scripts/check-upstream-boundary.sh HEAD; then
  echo
  echo "The merge succeeded but the boundary check failed. If it only lists missing"
  echo "permissions.deny rules, add them to .claude/settings.json in this branch."
  exit 1
fi

cat <<EOF

Merged $tag into $branch. Next:
  1. Build and test: ./build.sh
  2. git push -u origin $branch
  3. Open a PR into product/main and merge it with "Create a merge commit" only.
  4. Do not push upstream tags to origin: it starts the upstream release workflows.
EOF
