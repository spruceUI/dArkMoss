#!/bin/bash
# Pack the update payload: the boot partition plus everything this build put on
# top of Debian, applied in place on a running device by
# scripts/spruce/dmupd-apply.sh (shipped inside the payload as apply.sh).
#
# What ships is decided by the package database, not by a hand-kept list. A
# path is included when no dpkg package owns it, or when a package owns it and
# the build changed it (md5 mismatch, conffiles included). Debian's own files
# are left alone, and everything the dArkMoss scripts copy, append to, build or
# symlink over is picked up on its own. Files a package owns that the build
# deleted go into remove.list.
#
# Runs after cleanup_filesystem.sh, while Arkbuild is still mounted and the
# image's boot partition can be remounted from ${LOOP_DEV}p3.

echo -e "Packing the update payload...\n\n"

iName=$(echo ${UNIT} | tr '[:lower:]' '[:upper:]')
DMUPD_VERSION="${DARKMOSS_VERSION:-$BUILD_DATE}"
DMUPD="dArkMoss_${iName}_${DMUPD_VERSION}.dmupd"
WORK="$(mktemp -d)"

case "$UNIT" in
  rgb30)     DMUPD_PLATFORM="RGB30" ;;
  miniloong) DMUPD_PLATFORM="Miniloong" ;;
  *)         DMUPD_PLATFORM="" ;;
esac

# Device state and build-only artefacts, matched against absolute paths. The
# same list gates the layer and remove.list.
cat > "$WORK/exclude" <<'EOF'
^/etc/(passwd|shadow|group|gshadow|subuid|subgid)(-|$)
^/etc/(machine-id|hostname|hosts|fstab|localtime|timezone|adjtime|resolv\.conf|ld\.so\.cache|mtab|\.pwd\.lock|\.updated)$
^/etc/ssh/ssh_host_
^/etc/NetworkManager/system-connections(/|$)
^/etc/ssl/certs(/|$)
^/etc/alternatives(/|$)
^/etc/console-setup/cached
^/etc/systemd/system/multi-user\.target\.wants/firstboot\.service$
^/etc/apt/apt\.conf\.d/99proxy$
^/usr/bin/qemu-aarch64-static$
^/usr/sbin/policy-rc\.d$
^/usr/lib/locale(/|$)
^/usr/share/(man|doc|doc-base|lintian|mime|info/dir|applications/mimeinfo\.cache|glib-2\.0/schemas/gschemas\.compiled)(/|$)
/icon-theme\.cache$
/gconv-modules\.cache$
/__pycache__(/|$)
^/home/ark/(\.bash_history|\.cache|\.Xauthority|Arkbuild_ccache)(/|$)
^/(meson|debootstrap)(/|$)
^/etc/security/opasswd$
^/etc/\.java(/|$)
^/etc/xml/.*\.old$
^/usr/lib/udev/hwdb\.bin$
^/usr/lib/ccache(/|$)
^/usr/(local/)?include(/|$)
^/usr/lib/aarch64-linux-gnu/include(/|$)
^/usr/local/(man|src|games|libexec|etc)(/|$)
EOF

# Never delete firmware. The CI chroot cache leaves the firmware packages' files
# out of the tarball, so a cache-built rootfs reports them missing although a
# device flashed from a cold build has them and a USB dongle may need them.
cat > "$WORK/never-remove" <<'EOF'
^/usr/lib/firmware(/|$)
EOF

# dpkg records merged-/usr paths; fold the few legacy /lib, /bin, /sbin entries
# onto the same spelling find prints.
canon() { sed -E 's#^/(lib|lib64|bin|sbin)(/|$)#/usr/\1\2#'; }

sudo cat Arkbuild/var/lib/dpkg/info/*.list | canon | sort -u > "$WORK/owned"

{
  sudo find Arkbuild -mindepth 1 \
    \( -path Arkbuild/proc -o -path Arkbuild/sys -o -path Arkbuild/dev \
       -o -path Arkbuild/run -o -path Arkbuild/tmp -o -path Arkbuild/var \
       -o -path Arkbuild/boot -o -path Arkbuild/root \) -prune \
    -o \( -type f -o -type l -o -type d \) -printf '/%P\n'
  # /var is runtime state except for these two, which the build writes.
  sudo find Arkbuild/var/spool/cron/crontabs Arkbuild/var/local -mindepth 1 \
    \( -type f -o -type l -o -type d \) -printf '%p\n' 2>/dev/null | sed 's#^Arkbuild##'
} | sort -u > "$WORK/all"

comm -23 "$WORK/all" "$WORK/owned" > "$WORK/unowned"

# Owned files the build changed or removed. md5sums files cover regular files;
# conffiles carry their reference md5 in the status file instead.
# A dangling symlink also fails to open; it is something the build put there,
# so it ships rather than being deleted.
sudo bash -c 'cd Arkbuild && md5sum --quiet -c var/lib/dpkg/info/*.md5sums 2>/dev/null' \
  | sed -n 's/^\(.*\): FAILED open or read$/MISSING \/\1/p; t; s/^\(.*\): FAILED$/CHANGED \/\1/p' \
  | while read -r verdict path; do
      if [ "$verdict" = "MISSING" ] && [ -L "Arkbuild$path" ]; then
        echo "CHANGED $path"
      else
        echo "$verdict $path"
      fi
    done > "$WORK/verify"
sudo awk '
  /^Conffiles:/ { inblock = 1; next }
  /^ / && inblock { if ($2 != "newconffile") print $1, $2; next }
  { inblock = 0 }
' Arkbuild/var/lib/dpkg/status | while read -r path want; do
  if [ ! -e "Arkbuild$path" ]; then
    echo "MISSING $path"
  elif [ "$(sudo md5sum "Arkbuild$path" | cut -d' ' -f1)" != "$want" ]; then
    echo "CHANGED $path"
  fi
done >> "$WORK/verify"

sed -n 's/^CHANGED //p' "$WORK/verify" | canon | sort -u > "$WORK/changed"
sed -n 's/^MISSING //p' "$WORK/verify" | canon | sort -u | grep -Ev -f "$WORK/exclude" | grep -Ev -f "$WORK/never-remove" > "$WORK/remove.list"

sort -u "$WORK/unowned" "$WORK/changed" | grep -Ev -f "$WORK/exclude" | sed 's#^/##' > "$WORK/layer"

echo "Layer: $(wc -l < "$WORK/layer") paths, $(wc -l < "$WORK/remove.list") removals"
echo "Largest files in the layer:"
sudo bash -c 'cd Arkbuild && xargs -d "\n" stat -c "%s %F %n" 2>/dev/null' < "$WORK/layer" \
  | awk '$2 == "regular" {printf "%8d KiB  /%s\n", $1 / 1024, $NF}' | sort -rn | head -n 20

sudo tar -C Arkbuild --numeric-owner --no-recursion -T "$WORK/layer" -czf "$WORK/rootfs.tar.gz"

# --- boot partition ----------------------------------------------------------
# finishing_touches unmounted p3; remount it read-only to read the boot files.
# firstboot.sh, expandtoexfat.sh and fstab.exfat are first-boot only and
# already deleted on any device this could land on.
mkdir -p ${mountpoint}
sudo mount -o ro ${LOOP_DEV}p3 ${mountpoint}
sudo tar -C ${mountpoint} --numeric-owner \
  --exclude=./firstboot.sh --exclude=./expandtoexfat.sh --exclude=./fstab.exfat \
  -czf "$WORK/boot.tar.gz" .
sudo umount ${mountpoint}

# --- assemble ---------------------------------------------------------------
KVER=$(basename "$(find Arkbuild/usr/lib/modules -maxdepth 1 -mindepth 1 -type d | head -n 1)")
cat > "$WORK/manifest" <<EOF
format=darkmoss-update/1
unit=${UNIT}
spruce_platform=${DMUPD_PLATFORM}
version=${DMUPD_VERSION}
build=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
kernel=${KVER}
boot_sha256=$(sha256sum "$WORK/boot.tar.gz" | cut -d' ' -f1)
rootfs_sha256=$(sha256sum "$WORK/rootfs.tar.gz" | cut -d' ' -f1)
EOF
cp scripts/spruce/dmupd-apply.sh "$WORK/apply.sh"
chmod 0755 "$WORK/apply.sh"

sudo chown -R "$(id -u):$(id -g)" "$WORK"
rm -f "$DMUPD"
# Uncompressed outer tar, manifest first, so the head can be read without
# touching the rest.
tar -C "$WORK" --owner=0 --group=0 -cf "$DMUPD" manifest apply.sh remove.list boot.tar.gz rootfs.tar.gz

echo "Update payload: $DMUPD ($(du -h "$DMUPD" | cut -f1))"
cat "$WORK/manifest"
rm -rf "$WORK"
