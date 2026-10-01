#!/bin/sh
# Apply a dArkMoss update payload (.dmupd) to the running system.
#
# Shipped inside every payload as apply.sh and run from there by spruce's
# Firmware Update app, as root, with the frontend stopped. Usage:
#   apply.sh <payload.dmupd>
#
# The payload is an uncompressed tar: manifest, apply.sh, remove.list,
# boot.tar.gz (the boot partition), rootfs.tar.gz (every file the dArkMoss
# build added to or changed in the Debian rootfs), packages.tar.gz (every
# package that differs from dmupd-baseline.txt, whole, with its dpkg records)
# and resource.img.gz (U-Boot's resource partition: dtb, charging animation,
# power-on logo). Everything is checked against the manifest before anything
# is written. The rootfs layer and the packages go on first, then the boot
# files, renamed into place with the previous set kept in /boot/previous, then
# the resource partition is written whole, so a logo set with the Boot Logo app
# goes back to stock and that app has to be run again. A reboot afterwards is
# the caller's job.

set -u

PAYLOAD="${1:?usage: apply.sh <payload.dmupd>}"
BOOT=/boot
WORK="$(mktemp -d /var/tmp/dmupd.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

say()  { echo "dmupd: $*"; }
fail() { say "ERROR: $*"; exit 1; }
field() { sed -n "s/^$1=//p" "$WORK/manifest" | head -n 1; }

[ -f "$PAYLOAD" ] || fail "no such file: $PAYLOAD"
tar -xf "$PAYLOAD" -C "$WORK" manifest remove.list 2>/dev/null || fail "not a dArkMoss update payload"

[ "$(field format)" = "darkmoss-update/1" ] || fail "unsupported payload format '$(field format)'"

say "verifying payload"
GOT="$(tar -xOf "$PAYLOAD" rootfs.tar.gz | sha256sum | cut -d' ' -f1)"
[ "$GOT" = "$(field rootfs_sha256)" ] || fail "rootfs.tar.gz checksum mismatch"
GOT="$(tar -xOf "$PAYLOAD" boot.tar.gz | sha256sum | cut -d' ' -f1)"
[ "$GOT" = "$(field boot_sha256)" ] || fail "boot.tar.gz checksum mismatch"
HAVE_PACKAGES=0
if [ -n "$(field packages_sha256)" ]; then
    GOT="$(tar -xOf "$PAYLOAD" packages.tar.gz | sha256sum | cut -d' ' -f1)"
    [ "$GOT" = "$(field packages_sha256)" ] || fail "packages.tar.gz checksum mismatch"
    HAVE_PACKAGES=1
fi
RESOURCE_DEV=/dev/disk/by-partlabel/resource
HAVE_RESOURCE=0
if [ -n "$(field resource_sha256)" ]; then
    GOT="$(tar -xOf "$PAYLOAD" resource.img.gz | gzip -dc | sha256sum | cut -d' ' -f1)"
    [ "$GOT" = "$(field resource_sha256)" ] || fail "resource.img.gz checksum mismatch"
    [ -b "$RESOURCE_DEV" ] || fail "no resource partition at $RESOURCE_DEV"
    RESOURCE_SIZE="$(tar -xOf "$PAYLOAD" resource.img.gz | gzip -dc | wc -c)"
    RESOURCE_MAX="$(blockdev --getsize64 "$RESOURCE_DEV" 2>/dev/null || echo 0)"
    [ "$RESOURCE_SIZE" -le "$RESOURCE_MAX" ] || fail "resource image is $RESOURCE_SIZE bytes, partition is $RESOURCE_MAX"
    HAVE_RESOURCE=1
fi

# The unit is in os-release; images from before the SPRUCE_PLATFORM stamp only
# carry HW_DEVICE.
HAVE_PLATFORM="$(sed -n 's/^SPRUCE_PLATFORM="\(.*\)"/\1/p' /etc/os-release)"
if [ -z "$HAVE_PLATFORM" ]; then
    case "$(sed -n 's/^HW_DEVICE="\(.*\)"/\1/p' /etc/os-release)" in
        *Miniloong*) HAVE_PLATFORM="Miniloong" ;;
        *)           HAVE_PLATFORM="RGB30" ;;
    esac
fi
WANT_PLATFORM="$(field spruce_platform)"
[ "$WANT_PLATFORM" = "$HAVE_PLATFORM" ] || fail "payload is for $WANT_PLATFORM, this device is $HAVE_PLATFORM"

say "applying $(field version) ($(field build)) for $WANT_PLATFORM"

mountpoint -q "$BOOT" || mount "$BOOT" || fail "cannot mount $BOOT"
rm -rf "$BOOT/previous" "$BOOT/.new"
BOOT_NEED_KB="$(tar -xOf "$PAYLOAD" boot.tar.gz | gzip -dc | wc -c)"
BOOT_NEED_KB=$((BOOT_NEED_KB / 1024 + 1024))
BOOT_FREE_KB="$(df -k "$BOOT" | awk 'END {print $4}')"
[ "$BOOT_FREE_KB" -ge "$BOOT_NEED_KB" ] || fail "$BOOT has ${BOOT_FREE_KB}K free, need ${BOOT_NEED_KB}K"

# RGB30 image: rgb30versioncheck.sh swaps the dtb on /boot for the v2 board or
# the RGB20SX at every boot. Note which variant is live now so the same one is
# put back after the new boot files land, instead of one boot on the wrong dtb.
DTB_VARIANT=""
DTBS=/usr/local/bin/rgb30dtbs
if [ -f "$BOOT/rk3566-rgb30.dtb" ] && [ -d "$DTBS" ]; then
    if cmp -s "$DTBS/rk3566-rgb20sx.dtb" "$BOOT/rk3566-rgb30.dtb"; then
        DTB_VARIANT="rk3566-rgb20sx.dtb"
    elif cmp -s "$DTBS/rk3566-rgb20sx.dtb.v2" "$BOOT/rk3566-rgb30.dtb"; then
        DTB_VARIANT="rk3566-rgb20sx.dtb.v2"
    elif cmp -s "$DTBS/rk3566-rgb30.dtb.v2" "$BOOT/rk3566-rgb30.dtb"; then
        DTB_VARIANT="rk3566-rgb30.dtb.v2"
    fi
fi

# Everything above is read-only. From here on the system is being changed.
say "removing $(wc -l < "$WORK/remove.list") files the new build no longer ships"
while IFS= read -r path; do
    [ -n "$path" ] || continue
    rm -f -- "$path"
done < "$WORK/remove.list"

say "installing the rootfs layer"
# tar replaces a file by unlinking it and creating a new one, so binaries and
# libraries in use keep running on the old inode. --keep-directory-symlink
# protects the merged-/usr symlinks should a legacy /lib path ever appear in the
# layer; --no-overwrite-dir leaves existing directories' ownership and mode
# alone (it cannot be combined with --unlink-first).
tar -xOf "$PAYLOAD" rootfs.tar.gz | tar -xzpf - -C / --numeric-owner --keep-directory-symlink --no-overwrite-dir \
    || fail "rootfs layer did not extract cleanly"
sync

if [ "$HAVE_PACKAGES" = 1 ]; then
    tar -xOf "$PAYLOAD" packages.tar.gz | tar -xzf - -C "$WORK" pkgmeta || fail "package records did not extract"
    say "installing $(wc -l < "$WORK/pkgmeta/keys") packages"
    for arch in $(field foreign_arches); do
        dpkg --add-architecture "$arch"
    done
    while IFS=: read -r gname _ _ _; do
        getent group "$gname" >/dev/null || groupadd -r "$gname"
    done < "$WORK/pkgmeta/group"
    while IFS=: read -r uname _ _ ugid gecos home shell; do
        getent passwd "$uname" >/dev/null && continue
        gname="$(awk -F: -v g="$ugid" '$3 == g {print $1; exit}' "$WORK/pkgmeta/group")"
        useradd -r -M -d "$home" -s "$shell" -c "$gecos" ${gname:+-g "$gname"} "$uname"
    done < "$WORK/pkgmeta/passwd"
    tar -xOf "$PAYLOAD" packages.tar.gz | tar -xzpf - -C / --numeric-owner --keep-directory-symlink --no-overwrite-dir --exclude=pkgmeta \
        || fail "packages did not extract cleanly"
    STATUS=/var/lib/dpkg/status
    cp -p "$STATUS" "$STATUS-old"
    awk -v keys="$WORK/pkgmeta/keys" '
      BEGIN { while ((getline line < keys) > 0) skip[line] = 1; RS = ""; ORS = "\n\n" }
      { name = arch = ""
        n = split($0, f, "\n")
        for (i = 1; i <= n; i++) {
          if (f[i] ~ /^Package: /) name = substr(f[i], 10)
          if (f[i] ~ /^Architecture: /) arch = substr(f[i], 15)
        }
        if (!((name " " arch) in skip)) print }
    ' "$STATUS-old" > "$STATUS.dmupd" && cat "$WORK/pkgmeta/status" >> "$STATUS.dmupd" \
        && mv "$STATUS.dmupd" "$STATUS" || fail "dpkg status merge failed; $STATUS-old is the previous one"
    sync
fi

# The layer carries the build's enable symlinks; firstboot has already run here.
systemctl disable firstboot.service >/dev/null 2>&1
ldconfig
KVER="$(field kernel)"
[ -n "$KVER" ] && [ -d "/usr/lib/modules/$KVER" ] && depmod -a "$KVER" 2>/dev/null
systemctl daemon-reload 2>/dev/null

say "installing the boot files"
mkdir -p "$BOOT/.new" "$BOOT/previous"
tar -xOf "$PAYLOAD" boot.tar.gz | tar -xzf - -C "$BOOT/.new" || fail "boot files did not extract; the previous kernel is still in place"
sync
for entry in "$BOOT"/.new/* "$BOOT"/.new/.[!.]*; do
    [ -e "$entry" ] || continue
    name="${entry##*/}"
    [ -e "$BOOT/$name" ] && mv "$BOOT/$name" "$BOOT/previous/$name"
    mv "$entry" "$BOOT/$name"
done
rmdir "$BOOT/.new" 2>/dev/null

if [ -n "$DTB_VARIANT" ] && [ -f "$DTBS/$DTB_VARIANT" ]; then
    say "restoring the $DTB_VARIANT variant on /boot"
    cp -f "$DTBS/$DTB_VARIANT" "$BOOT/rk3566-rgb30.dtb"
fi
sync

if [ "$HAVE_RESOURCE" = 1 ]; then
    say "writing the resource partition"
    tar -xOf "$PAYLOAD" resource.img.gz | gzip -dc | dd of="$RESOURCE_DEV" bs=1M conv=fsync 2>/dev/null \
        || fail "resource partition write failed; the boot files and rootfs are already updated"
    sync
fi

say "done: $(sed -n 's/^OS_VERSION=//p' /etc/os-release | tr -d '"') is installed, reboot to run it"
exit 0
