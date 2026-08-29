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

# A GitHub release asset caps at 2GB. The prepared chroot came out at 1998MB -
# it fit with 50MB to spare, and one more package would have pushed it over,
# silently, because this cache fails soft. So anything past the threshold is
# split across numbered part assets and reassembled on the way back in, the same
# way the finished image is published.
BUILD_CACHE_SPLIT_MB="${BUILD_CACHE_SPLIT_MB:-1500}"

# bc_fetch <asset-name> <dest-path>
#
# Tries the whole asset first, then a split set. A split set is only trusted if
# its manifest is present and the reassembled sha256 matches - a half-uploaded
# set has to look like a miss, not like a corrupt tarball, or the caller extracts
# garbage over a good chroot.
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

    local mdir manifest parts want_sha i part got_sha
    mdir="$(mktemp -d)"
    if gh release download "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            --pattern "${asset}.manifest" --output "$mdir/manifest" --clobber >/dev/null 2>&1 \
       && [ -s "$mdir/manifest" ]; then
        parts="$(grep '^parts=' "$mdir/manifest" | cut -d= -f2)"
        want_sha="$(grep '^sha256=' "$mdir/manifest" | cut -d= -f2)"
        if [ -n "$parts" ] && [ -n "$want_sha" ]; then
            echo "build-cache: $asset is split into $parts parts, fetching"
            i=0
            while [ "$i" -lt "$parts" ]; do
                part="$(printf '%s.part%03d' "$asset" "$i")"
                if ! gh release download "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
                        --pattern "$part" --output "$mdir/$part" --clobber >/dev/null 2>&1 \
                   || [ ! -s "$mdir/$part" ]; then
                    echo "build-cache: part $part missing - treating as a miss"
                    rm -rf "$mdir"; rm -f "$dest"
                    return 1
                fi
                i=$((i + 1))
            done
            cat "$mdir"/"$asset".part[0-9][0-9][0-9] > "$dest" 2>/dev/null
            got_sha="$(sha256sum "$dest" | cut -d' ' -f1)"
            rm -rf "$mdir"
            if [ "$got_sha" = "$want_sha" ]; then
                echo "build-cache: HIT  $asset (reassembled, sha ok)"
                return 0
            fi
            echo "build-cache: reassembled $asset failed its checksum - treating as a miss"
            rm -f "$dest"
            return 1
        fi
    fi
    rm -rf "$mdir"

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

    local size_mb stagedir
    size_mb="$(du -m "$file" | cut -f1)"
    stagedir="$(mktemp -d)"

    if [ "$size_mb" -le "$BUILD_CACHE_SPLIT_MB" ]; then
        cp -f "$file" "$stagedir/$asset" || { rm -rf "$stagedir"; return 0; }
        if gh release upload "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
                "$stagedir/$asset" --clobber >/dev/null 2>&1; then
            echo "build-cache: published $asset (${size_mb}MB)"
        else
            echo "build-cache: could not publish $asset - continuing"
        fi
        rm -rf "$stagedir"
        return 0
    fi

    # Too big for one asset. Split, upload the parts, and only then upload the
    # manifest - it is what bc_fetch trusts, so it must not exist until every
    # part it names does. An interrupted publish then reads as a miss.
    echo "build-cache: $asset is ${size_mb}MB, splitting at ${BUILD_CACHE_SPLIT_MB}MB"
    split -b "${BUILD_CACHE_SPLIT_MB}m" -d -a 3 "$file" "$stagedir/${asset}.part" || {
        rm -rf "$stagedir"; return 0; }

    local nparts sha
    nparts="$(ls -1 "$stagedir/${asset}.part"* 2>/dev/null | wc -l)"
    sha="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$nparts" -lt 1 ]; then rm -rf "$stagedir"; return 0; fi

    if ! gh release upload "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            "$stagedir/${asset}.part"* --clobber >/dev/null 2>&1; then
        echo "build-cache: could not publish the parts of $asset - continuing"
        rm -rf "$stagedir"
        return 0
    fi

    printf 'parts=%s\nsha256=%s\n' "$nparts" "$sha" > "$stagedir/${asset}.manifest"
    if gh release upload "$BUILD_CACHE_TAG" --repo "$BUILD_CACHE_REPO" \
            "$stagedir/${asset}.manifest" --clobber >/dev/null 2>&1; then
        echo "build-cache: published $asset as $nparts parts (${size_mb}MB)"
    else
        echo "build-cache: parts uploaded but manifest failed - next build will treat it as a miss"
    fi
    rm -rf "$stagedir"
    return 0
}
