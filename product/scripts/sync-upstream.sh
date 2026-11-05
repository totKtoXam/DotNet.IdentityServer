#!/usr/bin/env bash
# Prepares a branch that merges an upstream release tag into product/main.
#
# Usage: product/scripts/sync-upstream.sh <upstream-tag>
#   e.g. product/scripts/sync-upstream.sh 3.1.3
#
# The result is a local branch sync/upstream-<tag> with a merge commit that also records
# the new baseline in product/UPSTREAM_BASELINE. Push it and open a PR into product/main
# that is merged with "Create a merge commit" (never squash or rebase).
# Upstream tags are not pushed to origin: CI fetches them from upstream itself.

set -euo pipefail

upstream_url=https://github.com/RockSolidKnowledge/Open.IdentityServer.git
baseline_path=product/UPSTREAM_BASELINE
tag=${1:?usage: sync-upstream.sh <upstream-tag>}
branch="sync/upstream-$tag"
base=origin/product/main

die() { echo "error: $*" >&2; exit 1; }

[[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
  || die "'$tag' is not an upstream release tag (plain semver, e.g. 3.1.3)"

cd "$(git rev-parse --show-toplevel)"

[[ -z $(git status --porcelain) ]] || die "working tree is not clean"
! git show-ref --verify --quiet "refs/heads/$branch" || die "branch $branch already exists"
[[ $(git rev-parse --is-shallow-repository) == false ]] \
  || die "shallow clone: run 'git fetch --unshallow origin' first"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$upstream_url"
fi

git fetch upstream --tags \
  || die "fetching upstream tags failed. If git reported 'would clobber existing tag', a local numeric tag
       differs from upstream: numeric tags belong to upstream, delete the local one and retry."
git ls-remote --exit-code --tags upstream "refs/tags/$tag" >/dev/null \
  || die "tag $tag does not exist in upstream"
git fetch origin product/main

tag_commit=$(git rev-parse "refs/tags/$tag^{commit}")
baseline_text=$(git show "$base:$baseline_path" 2>/dev/null) || die "$baseline_path is missing on product/main"
current_commit=$(sed -n 's/^commit=//p' <<< "$baseline_text" | head -n 1)
current_tag=$(sed -n 's/^tag=//p' <<< "$baseline_text" | head -n 1)
[[ -n $current_commit ]] || die "$baseline_path on product/main has no commit= line"

if git merge-base --is-ancestor "$tag_commit" "$current_commit"; then
  echo "product/main is already based on $current_tag, which contains $tag; nothing to do"
  exit 0
fi
git merge-base --is-ancestor "$current_commit" "$tag_commit" \
  || die "$tag does not descend from the current baseline $current_tag; sync only newer releases of the same line"

git switch -c "$branch" "$base"

write_baseline() {
  {
    echo "# Upstream release merged into this branch. Written by product/scripts/sync-upstream.sh; do not edit by hand."
    echo "tag=$tag"
    echo "commit=$tag_commit"
  } > "$baseline_path"
  git add "$baseline_path"
}

if ! git merge --no-ff --no-commit "refs/tags/$tag"; then
  if ! git rev-parse -q --verify MERGE_HEAD >/dev/null; then
    git switch -q -
    git branch -q -D "$branch"
    die "git merge failed before merging anything (see above); branch $branch removed"
  fi
  write_baseline
  echo
  echo "Merge conflicts in:"
  git diff --name-only --diff-filter=U | sed 's/^/  - /'
  echo
  echo "Resolve them: take the upstream version and re-apply the FORK-PATCH changes listed in"
  echo "product/UPSTREAM_PATCHES.md (drop entries that upstream made unnecessary). Then:"
  echo "  git add <files>"
  echo "  git commit -m 'Merge upstream $tag into product/main'"
  echo "  product/scripts/check-upstream-boundary.sh"
  exit 1
fi

write_baseline
git commit -q -m "Merge upstream $tag into product/main"

echo
if ! product/scripts/check-upstream-boundary.sh HEAD; then
  echo
  echo "The merge succeeded but the boundary check failed. If it only lists missing"
  echo "permissions.deny rules, a human adds them to .claude/settings.json in this branch."
  exit 1
fi

cat <<EOF

Merged $tag into $branch. Next:
  1. Build and test: ./build.sh (and the product solution, if any)
  2. git push -u origin $branch
  3. Open a PR into product/main and merge it with "Create a merge commit" only.
  4. Do not push upstream tags to origin: it starts the upstream release workflows.
EOF
