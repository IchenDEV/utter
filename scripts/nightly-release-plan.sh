#!/usr/bin/env bash
#
# Nightly release candidates: decide whether `main` has moved since the latest
# release tag and, if so, print the next patch version.
#
# Read-only. It never creates tags or commits; the nightly workflow performs the
# write action after a human-reviewed change is merged.
#
# Usage: nightly-release-plan.sh <repository> [branch]
#   repository  path to a git checkout (defaults are resolved by the caller)
#   branch      branch whose tip is compared (default: origin/main)
#
# Output (stdout), in this order when a release is warranted:
#   version=<X.Y.Z>              next patch version, validated by release-version.sh
#   latest_tag=<vX.Y.Z>          latest stable release tag, if any
#   head_sha=<sha>               commit the tag will be created on
#   commit_count=<n>             commits on the branch since that tag
#   commit_summary=<one line>    newest commit subjects, newest first
#
# Prints `changed=false` plus a `reason=` line and exits 0 when nothing should be
# released (no stable tag yet is treated as "release", with `latest_tag=` empty).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_VERSION="$SCRIPT_DIR/release-version.sh"

REPOSITORY="${1:-}"
BRANCH="${2:-origin/main}"

if [ -z "$REPOSITORY" ]; then
    echo "usage: $0 <repository> [branch]" >&2
    exit 2
fi
# `.git` may be a directory (normal clone) or a file (worktree/submodule), so
# ask git itself rather than testing for the directory.
if ! git -C "$REPOSITORY" rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: $REPOSITORY is not a git checkout" >&2
    exit 1
fi

# Stable release tags only, highest by version order (`v0.0.10` > `v0.0.9`).
latest_tag=""
while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    if "$RELEASE_VERSION" "$tag" >/dev/null 2>&1; then
        latest_tag="$tag"
    fi
done < <(git -C "$REPOSITORY" tag -l 'v*' | sort -V)

head_sha="$(git -C "$REPOSITORY" rev-parse --verify "${BRANCH}^{commit}" 2>/dev/null || true)"
if [ -z "$head_sha" ]; then
    echo "error: cannot resolve branch '$BRANCH' in $REPOSITORY" >&2
    exit 1
fi

if [ -z "$latest_tag" ]; then
    commit_count="$(git -C "$REPOSITORY" rev-list --count "$head_sha")"
    next_version="0.0.1"
    range_summary="$(git -C "$REPOSITORY" log --max-count=10 --pretty=format:'%h %s' "$head_sha")"
else
    if ! git -C "$REPOSITORY" merge-base --is-ancestor "$latest_tag" "$head_sha" 2>/dev/null; then
        echo "error: latest tag $latest_tag is not an ancestor of $BRANCH" >&2
        exit 1
    fi
    commit_count="$(git -C "$REPOSITORY" rev-list --count "$latest_tag..$head_sha")"
    if [ "$commit_count" -eq 0 ]; then
        echo "changed=false"
        echo "reason=no commits on $BRANCH since $latest_tag"
        echo "latest_tag=$latest_tag"
        echo "head_sha=$head_sha"
        echo "commit_count=0"
        exit 0
    fi
    # Next patch version; refuse to guess past patch 9_999_999.
    numeric="$("$RELEASE_VERSION" "$latest_tag")"
    major="${numeric%%.*}"
    rest="${numeric#*.}"
    minor="${rest%%.*}"
    patch="${rest##*.}"
    next_version="$major.$minor.$((patch + 1))"
    range_summary="$(git -C "$REPOSITORY" log --max-count=10 --pretty=format:'%h %s' "$latest_tag..$head_sha")"
fi

# The generated tag must itself pass the release validator.
"$RELEASE_VERSION" "v$next_version" >/dev/null

# Single-line summary for `$GITHUB_OUTPUT`; keep any `%` intact.
commit_summary="$(printf '%s' "$range_summary" | tr '\n' ';' | tr -d '\r')"

echo "changed=true"
echo "version=$next_version"
echo "latest_tag=$latest_tag"
echo "head_sha=$head_sha"
echo "commit_count=$commit_count"
echo "commit_summary=$commit_summary"
