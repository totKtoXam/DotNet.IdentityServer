#!/usr/bin/env bash
# Prepares a branch that merges an upstream release tag into product/main.
#
# Usage: product/scripts/sync-upstream.sh <upstream-tag>
#   e.g. product/scripts/sync-upstream.sh 2.1.0
#
# The result is a local branch sync/upstream-<tag>. Push it and open a PR
# into product/main that is merged with "Create a merge commit" (never squash).

set -euo pipefail

tag=${1:?usage: sync-upstream.sh <upstream-tag>}
upstream_url=https://github.com/RockSolidKnowledge/Open.IdentityServer.git
branch="sync/upstream-$tag"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$upstream_url"
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "error: working tree is not clean" >&2
  exit 1
fi

git fetch upstream --tags
git fetch origin product/main

if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null; then
  echo "error: tag '$tag' not found in upstream" >&2
  exit 1
fi

if git merge-base --is-ancestor "$tag" origin/product/main; then
  echo "product/main already contains $tag, nothing to do"
  exit 0
fi

git switch -c "$branch" origin/product/main

if ! git merge --no-ff --no-edit -m "Merge upstream $tag into product/main" "$tag"; then
  echo
  echo "Merge conflicts in:"
  git diff --name-only --diff-filter=U | sed 's/^/  - /'
  echo
  echo "Resolve them (keep upstream code, re-apply patches from product/UPSTREAM_PATCHES.md),"
  echo "then: git add <files> && git commit"
  exit 1
fi

echo
echo "Merged $tag into $branch. Next:"
echo "  1. build and test: ./build.sh"
echo "  2. git push -u origin $branch"
echo "  3. open a PR into product/main and merge it with 'Create a merge commit'"
