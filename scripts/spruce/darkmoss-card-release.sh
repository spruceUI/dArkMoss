#!/bin/bash
# Stop step of darkmoss-card-release.service: end what still holds the spruce card, so that
# mnt-SDCARD.mount stops clean. spruce-launch is KillMode=process, so spruce's helpers outlive it.
CARD="${1:-/mnt/SDCARD}"
mountpoint -q "$CARD" || exit 0

# PIDs with a cwd, exe, root, open file or mapping under the card. Matched by path, never by
# filesystem, so a missing mount cannot widen this to the rootfs.
holders() {
  {
    find /proc/[0-9]*/cwd /proc/[0-9]*/exe /proc/[0-9]*/root /proc/[0-9]*/fd -maxdepth 1 \
      \( -lname "$CARD" -o -lname "$CARD/*" \) -print 2>/dev/null
    grep -ls " $CARD/" /proc/[0-9]*/maps 2>/dev/null
  } | sed -n 's|^/proc/\([0-9]*\)/.*|\1|p' | sort -un | grep -vx -e 1 -e "$$"
}

names() {
  for pid in "$@"; do
    read -r comm 2>/dev/null < "/proc/$pid/comm" && printf ' %s(%s)' "$comm" "$pid"
  done
}

pids="$(holders)"
[ -n "$pids" ] || exit 0
# shellcheck disable=SC2086
echo "card-release: ending$(names $pids)"
# shellcheck disable=SC2086
kill -TERM $pids 2>/dev/null

# 3 s for a clean exit (an emulator writing its save), then no more waiting.
for _ in {1..15}; do
  sleep 0.2
  pids="$(holders)"
  [ -n "$pids" ] || exit 0
done
# shellcheck disable=SC2086
echo "card-release: still there after 3 s, killing$(names $pids)"
# shellcheck disable=SC2086
kill -KILL $pids 2>/dev/null
for _ in {1..10}; do
  sleep 0.1
  pids="$(holders)"
  [ -n "$pids" ] || exit 0
done
# shellcheck disable=SC2086
echo "card-release: card still held by$(names $pids)"
exit 0
