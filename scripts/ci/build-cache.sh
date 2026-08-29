#!/bin/bash
# Park expensive, deterministic build artifacts as assets on a GitHub release,
# so later builds download them instead of rebuilding them.
#
# Why a release and not actions/cache: the Actions cache evicts entries after
# seven days without a hit and is capped per repo. This repo builds in bursts
# with weeks of quiet in between, so eviction would land on exactly the build
# where a 2.5h cold run hurts most. A release asset stays until deleted.
#
# Everything here fails soft. No gh, no token, no release, no matching asset, a
# network blip - all of it just returns non-zero and the caller builds the
# artifact the way it always did. A broken cache must never be able to break a
# build; the worst it may cost is the time it was meant to save.
#
# Keys are content hashes of the real inputs, so a changed input misses and
# rebuilds on its own. Nothing here needs manual invalidation.

BUILD_CACHE_TAG="${BUILD_CACHE_TAG:-build-cache}"
BUILD_CACHE_REPO="${BUILD_CACHE_REPO:-${GITHUB_REPOSITORY:-spruceUI/dArkMoss}}"

bc_available() {
    command -v gh >/dev/null 2>&1 || return 1
    [ -n "${GH_TOKEN}${GITHUB_TOKEN}" ] || return 1
    return 0
}

# bc_key <input>...  ->  16-char hash. An argument that names a file is hashed
# by content; anything else is hashed as a literal string.
bc_key() {
    local acc="" item
    for item in "$@"; do
        if [ -f "$item" ]; then
            acc="${acc}$(sha256sum "$item" | cut -d' ' -f1)"
        else
            acc="${acc}${item}"
        fi
    done
    printf '%s' "$acc" | sha256sum | cut -c1-16
}

# bc_remote_sha <git-url> [ref] -> the remote's current SHA, for keying an
# artifact built from a shallow clone of a moving branch.
bc_remote_sha() {
    git ls-remote "$1" "${2:-HEAD}" 2>/dev/null | awk '{print $1; exit}'
}

# bc_fetch <asset-name> <dest-path>
bc_fetch() {
    bc_available || { echo "build-cache: unavailable, building normally"; return 1; }
    local asset="$1" dest="$2"
    rm -f "$dest"
    if gh release download "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            --pattern "$asset" --output "$dest" --clobber >/dev/null 2>&1 \
       && [ -s "$dest" ]; then
        echo "build-cache: HIT  $asset"
        return 0
    fi
    echo "build-cache: MISS $asset"
    rm -f "$dest"
    return 1
}

# bc_publish <asset-name> <file>
#
# The asset takes the file's basename, so the file is staged under the asset
# name first. Always returns 0: failing to save a cache entry is not a build
# failure.
bc_publish() {
    bc_available || return 0
    local asset="$1" file="$2"
    [ -s "$file" ] || { echo "build-cache: nothing to publish for $asset"; return 0; }

    if ! gh release view "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" >/dev/null 2>&1; then
        gh release create "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            --title "Build cache" \
            --notes "Prebuilt intermediates keyed by input hash. Not a release - see scripts/ci/build-cache.sh. Safe to delete any asset; the next build rebuilds and republishes it." \
            --latest=false >/dev/null 2>&1 || true
    fi

    local stage
    stage="$(mktemp -d)/$asset"
    mkdir -p "$(dirname "$stage")"
    cp -f "$file" "$stage" || return 0
    if gh release upload "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            "$stage" --clobber >/dev/null 2>&1; then
        echo "build-cache: published $asset ($(du -h "$stage" | cut -f1))"
    else
        echo "build-cache: could not publish $asset - continuing"
    fi
    rm -rf "$(dirname "$stage")"
    return 0
}
