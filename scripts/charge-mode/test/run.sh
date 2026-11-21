#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Host test for charge-mode.sh, its initramfs hook and init-charge (TwigUI-Next's charge-mode test, adapted) under
# busybox ash in bwrap: fake /sys, FIFO key nodes, a file for fb0 and a gunzip stub that logs what
# is drawn. Needs bwrap + busybox on a Linux host.
#   test/run.sh [quick]   quick skips the blank/wake case (about 70 s)
#   test/run.sh install   only case 0 (install.sh per unit; plain bash, no bwrap: runs on macOS too)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
# frozen copies: ash reads scripts as it runs
cp "$HERE/charge-mode.sh" "$T/charge-mode.sh"; cp "$HERE/darkmoss-charge" "$T/darkmoss-charge"
cp "$HERE/init-charge" "$T/init-charge"
fails=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=$((fails + 1)); }

# 0: install.sh with each CI unit's UNIT as its build_<unit>.sh exports it (the RG353M's is 353m):
# opted in, its frames there, and the right entry (the initramfs hook; init-charge on the V10).
# sudo only logs; Arkbuild is a stand-in with the busybox the V10 check looks for.
REPO="$(cd "$HERE/../.." && pwd)"
mkdir -p "$T/inst/Arkbuild/bin"; ln -s "$REPO/scripts" "$T/inst/scripts"
printf '#!/bin/sh\n' > "$T/inst/Arkbuild/bin/busybox"; chmod +x "$T/inst/Arkbuild/bin/busybox"
install_log() { (cd "$T/inst" && UNIT=$1 bash -c 'sudo() { echo "sudo $*"; }; source scripts/charge-mode/install.sh
  echo "CHARGE_MODE=$CHARGE_MODE"' 2>&1); }
HOOK="sudo install -D -m 0755 scripts/charge-mode/darkmoss-charge "
INITC="sudo install -D -m 0755 scripts/charge-mode/init-charge "
# CI units left out on purpose (they must install nothing): the G350 and A10 Mini (no plug-in start),
# the RG353M (no unit to test on), the E5 Plus (its own charging screen, scripts/e5plus),
# the RG351P (not opted in).
NOT_IN=" g350 a10mini 353m e5plus rg351p "
for u in $(cat "$REPO/.github/units.txt"); do
  unit=$(sed -n 's/^export UNIT=//p' "$REPO/build_$u.sh"); out=$(install_log "$unit"); fr="$REPO/scripts/charge-mode/frames/$unit"
  if [[ "$NOT_IN" == *" $unit "* ]]; then
    grep -qx "CHARGE_MODE=n" <<< "$out" && ! grep -q "sudo install\|sudo cp" <<< "$out" \
      && ok "install.sh $u (UNIT=$unit): left out on purpose, installs nothing" || bad "install.sh $u (UNIT=$unit): $(tr '\n' '|' <<< "$out")"
    continue
  fi
  { [ -f "$fr/level-100.raw.gz" ] && [ -f "$fr/fb" ]; } || ls "$fr"/w*/fb > /dev/null 2>&1 || out="$out|no frames in $fr"
  if [ "$unit" = v10 ]; then want="$INITC"; nowant="$HOOK"; else want="$HOOK"; nowant="$INITC"; fi
  case "$out" in *"no frames in"*) bad "install.sh $u (UNIT=$unit): $out" ;;
    *) grep -qx "CHARGE_MODE=y" <<< "$out" && grep -qF "sudo cp -r scripts/charge-mode/frames/$unit/. " <<< "$out" &&
       grep -qF "$want" <<< "$out" && ! grep -qF "$nowant" <<< "$out" \
       && ok "install.sh $u (UNIT=$unit): opted in, frames/$unit, ${want#*charge-mode/}" || bad "install.sh $u (UNIT=$unit): $(tr '\n' '|' <<< "$out")" ;;
  esac
done
out=$(install_log 353v)
grep -qx "CHARGE_MODE=n" <<< "$out" && ! grep -q "sudo install\|sudo cp" <<< "$out" \
  && ok "install.sh: a unit not opted in (353v) installs nothing" || bad "install.sh 353v: $(tr '\n' '|' <<< "$out")"
# What build_update.sh removes on a unit left out: the entries and every frames file, nothing else.
out=$(cd "$T/inst" && UNIT=g350 bash -c 'sudo() { :; }; source scripts/charge-mode/install.sh; charge_mode_paths' 2>&1)
want="/etc/initramfs-tools/scripts/local-bottom/darkmoss-charge /usr/local/lib/darkmoss-charge/charge-mode.sh
  /usr/local/lib/darkmoss-charge/init-charge /usr/local/share/darkmoss-charge/level-100.raw.gz
  /usr/local/share/darkmoss-charge/fb /usr/local/share/darkmoss-charge/w720/booting.raw.gz"
miss=""; for p in $want; do grep -qxF "$p" <<< "$out" || miss="$miss $p"; done
stray=$(grep -vE '^/(etc/initramfs-tools/scripts/local-bottom/darkmoss-charge|usr/local/(lib|share)/darkmoss-charge/[^ ]+)$' <<< "$out")
[ -z "$miss" ] && [ -z "$stray" ] && ok "charge_mode_paths: $(wc -l <<< "$out") paths for a unit's update to remove" \
  || bad "charge_mode_paths: missing [$miss] stray [$(tr '\n' '|' <<< "$stray")]"
if [ "${1:-}" = install ]; then echo "$fails failure(s)"; [ "$fails" = 0 ]; exit; fi

# mkframe FILE BYTE: a 4x2 XRGB8888 frame (32 bytes) of one byte value, gzipped.
mkframe() { printf "$(printf '\\x%02x' $(for _ in $(seq 32); do echo "$2"; done))" | gzip -n > "$1"; }
fbhex() { od -An -tx1 -v "$T/root/storage/fb0" | tr -d ' \n'; }
rows() { for _ in $(seq $((16 * $1))); do printf %s "$2"; done; }   # hex of N 4-px rows of byte $2

setup() {
  rm -rf "$T/root"; mkdir -p "$T/root"; cd "$T/root" || exit 1
  mkdir -p sys/class/power_supply/{ac,usb,rk817-battery} sys/class/graphics/fb0 \
    sys/devices/system/cpu/cpufreq/policy0 devinput storage frames bin fake
  echo Mains > sys/class/power_supply/ac/type; echo USB > sys/class/power_supply/usb/type
  echo Battery > sys/class/power_supply/rk817-battery/type
  echo 0 > sys/class/power_supply/ac/online; echo 1 > sys/class/power_supply/usb/online
  echo 42 > sys/class/power_supply/rk817-battery/capacity
  # fb0: 4x2 visible, double height virtual, XRGB8888
  echo 0 > sys/class/graphics/fb0/blank; echo 16 > sys/class/graphics/fb0/stride
  echo 32 > sys/class/graphics/fb0/bits_per_pixel; echo 4,4 > sys/class/graphics/fb0/virtual_size
  echo 0,0 > sys/class/graphics/fb0/pan
  head -c 64 /dev/zero > storage/fb0
  echo schedutil > sys/devices/system/cpu/cpufreq/policy0/scaling_governor
  # power key, a headset (no keys), gpio-keys (keys only), a joypad with sticks
  i=0
  for dev in "rk805 pwrkey:100000 0 0 0:0" "rk817 Headset:0:0" "gpio-keys:c000000000000 0:0" \
             "GO-Super Gamepad:ffff 0 0 0 0:3003"; do
    IFS=: read -r name key abs <<< "$dev"
    mkdir -p "sys/class/input/event$i/device/capabilities"
    echo "$name" > "sys/class/input/event$i/device/name"
    echo "$key" > "sys/class/input/event$i/device/capabilities/key"
    echo "$abs" > "sys/class/input/event$i/device/capabilities/abs"
    mkfifo "devinput/event$i"; i=$((i + 1))
  done
  for l in $(seq 0 5 100); do mkframe "frames/level-$(printf %03d "$l").raw.gz" $((l / 5 + 1)); done
  mkframe frames/booting.raw.gz 238; echo "4 2" > frames/fb
  printf '#!/bin/sh\necho "$*" >> /storage/draw.log\nexec /usr/bin/busybox gunzip "$@"\n' > bin/gunzip
  # chvt logs the VT; the printk file stands in for /proc/sys/kernel/printk
  printf '#!/bin/sh\necho "$1" >> /storage/vt.log\n' > bin/chvt
  printf '7\t4\t1\t7\n' > storage/printk
  # a plug-in power-on (rk808's probe line) on a cold boot (boot-mode register 0) of an RK3326
  echo "[    1.52] rk808 0-0020: source: on=0x40, off=0x08" > fake/dmesg
  printf 'rockchip,rk3326-odroidgo3-linux\0rockchip,rk3326\0' > fake/compatible
  echo 0xff010200 > fake/reg; echo 0x00000000 > fake/devmem
  printf '#!/bin/sh\ncat /fake/dmesg\n' > bin/dmesg
  printf '#!/bin/sh\n[ "$1 $2" = "$(cat /fake/reg) 32" ] && [ -s /fake/devmem ] && cat /fake/devmem\n' > bin/devmem
  chmod +x bin/*
  for a in sh cat cut wc dd tr kill rm usleep sleep sed tail mv; do ln -s /usr/bin/busybox "bin/$a"; done
}

# ev FD TYPE CODE VALUE: one 64-bit struct input_event (zero time) into an open FIFO fd.
ev() { printf "$(printf '\\x%02x' 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 $(($2 & 255)) $(($2 >> 8)) \
  $(($3 & 255)) $(($3 >> 8)) $(($4 & 255)) 0 0 0)" >&"$1"; }
press() { ev "$1" 1 "$2" 1; ev "$1" 0 0 0; ev "$1" 1 "$2" 0; ev "$1" 0 0 0; }

ENV=()   # extra --setenv pairs for the next start
start() {
  bwrap --unshare-all --die-with-parent --new-session "${ENV[@]}" \
    --ro-bind /usr/lib /usr/lib --symlink usr/lib /lib --ro-bind /usr/bin/busybox /usr/bin/busybox \
    --proc /proc --dev /dev --tmpfs /tmp \
    --bind "$T/root/sys" /sys --bind "$T/root/devinput" /dev/input --bind "$T/root/storage" /storage \
    --bind "$T/root/frames" /frames --bind "$T/root/bin" /bin --ro-bind "$T/root/fake" /fake \
    --ro-bind "$T/charge-mode.sh" /charge-mode.sh \
    --setenv PATH /bin --setenv CHARGE_MODE_LOG /storage/charge.log --setenv CHARGE_MODE_PRINTK /storage/printk \
    --setenv CHARGE_MODE_FB /storage/fb0 --setenv CHARGE_MODE_DT /fake/compatible \
    /bin/sh /charge-mode.sh /frames &
  PID=$!
  # read-write opens never block, even if the sandbox failed to start
  exec 3<>"$T/root/devinput/event0" 4<>"$T/root/devinput/event2" 5<>"$T/root/devinput/event3"
}
finish() { exec 3>&- 4>&- 5>&-; }
waitrc() { local n=0; while kill -0 "$PID" 2>/dev/null && [ $n -lt "$1" ]; do sleep 0.25; n=$((n + 1)); done
  if kill -0 "$PID" 2>/dev/null; then kill "$PID"; wait "$PID" 2>/dev/null; RC=timeout; else wait "$PID"; RC=$?; fi; }
S() { cat "$T/root/$1" 2>/dev/null; }

# 1: lit screen, power key boots: level frame first, the boot logo last, governor restored; charge
# mode runs on VT 2 with console messages muted, and gives both back. Keys: the power key by name,
# key-only nodes as pads, the joypad with sticks and the keyless headset left out. (Every case that
# enters waits 5 s first: the charger has to stay online for 3 s before anything is drawn.)
setup; start; sleep 5
[ "$(S storage/vt.log)" = 2 ] && [ "$(S storage/printk)" = 1 ] && ok "on VT 2, console muted" || bad "vt '$(S storage/vt.log)' printk '$(S storage/printk)'"
[ "$(fbhex)" = "$(rows 2 09)$(rows 2 00)" ] && ok "level-040 drawn at the top of fb0" || bad "fb0 $(fbhex)"
press 3 116; waitrc 20; finish
[ "$RC" = 0 ] && ok "power key -> exit 0" || bad "power key -> rc $RC"
[ "$(head -1 storage/draw.log)" = "-c /frames/level-040.raw.gz" ] && ok "first frame level-040" || bad "first frame: $(head -1 storage/draw.log)"
[ "$(tail -1 storage/draw.log)" = "-c /frames/booting.raw.gz" ] && [ "$(fbhex)" = "$(rows 2 ee)$(rows 2 00)" ] \
  && ok "boot logo after power" || bad "last frame: $(tail -1 storage/draw.log), fb0 $(fbhex)"
[ "$(S storage/vt.log | tr '\n' ' ')" = "2 1 " ] && [ "$(S storage/printk)" = 7 ] && ok "VT 1 and loglevel 7 back" || bad "vt '$(S storage/vt.log | tr '\n' ' ')' printk '$(S storage/printk)'"
[ "$(S sys/devices/system/cpu/cpufreq/policy0/scaling_governor)" = schedutil ] && ok "governor restored" || bad "governor $(S sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
grep -q "power key /dev/input/event0, pads /dev/input/event2$" storage/charge.log && ok "power key by name, key-only pads" || bad "nodes: $(grep charging storage/charge.log)"
grep -q "boot-mode=0x00000000, usb online: charger power-on$" storage/charge.log && ok "the online supply is logged" || bad "entry: $(head -1 storage/charge.log)"

# 1b: the 4.4 power key name; fb0 panned to its second buffer: frames go there.
setup; echo rk8xx_pwrkey > sys/class/input/event0/device/name; echo 0,2 > sys/class/graphics/fb0/pan
start; sleep 4.5
grep -q "power key /dev/input/event0" storage/charge.log && ok "rk8xx_pwrkey found" || bad "nodes: $(cat storage/charge.log)"
[ "$(fbhex)" = "$(rows 2 00)$(rows 2 09)" ] && ok "drawn at the pan offset" || bad "fb0 $(fbhex)"
press 3 116; waitrc 20; finish
[ "$RC" = 0 ] && ok "then power -> exit 0" || bad "rc $RC"

# 2: a pad press while lit does not boot; a level change redraws; charger gone 3 s -> exit 2.
setup; start; sleep 5
press 4 115; sleep 1
echo 47 > sys/class/power_supply/rk817-battery/capacity; sleep 1
[ "$(tail -1 storage/draw.log)" = "-c /frames/level-045.raw.gz" ] && ok "redraw on level change" || bad "after level change: $(tail -1 storage/draw.log)"
kill -0 "$PID" 2>/dev/null && ok "pad press while lit keeps charging" || bad "exited on a pad press"
echo 0 > sys/class/power_supply/usb/online; sleep 1.5
kill -0 "$PID" 2>/dev/null && ok "still up 1.5 s after unplug" || bad "powered off too early"
waitrc 20; finish
[ "$RC" = 2 ] && ok "charger gone -> exit 2" || bad "charger gone -> rc $RC"
grep -q "charger removed at 47%" storage/charge.log && ok "logged removal" || bad "log: $(tail -1 storage/charge.log)"
[ "$(tail -1 storage/vt.log)" = 1 ] && [ "$(S storage/printk)" = 7 ] && ok "VT and loglevel back before power off" || bad "vt '$(S storage/vt.log | tr '\n' ' ')' printk '$(S storage/printk)'"

# 3: a blip of the charger shorter than 3 s is ignored.
setup; start; sleep 5
echo 0 > sys/class/power_supply/usb/online; sleep 1; echo 1 > sys/class/power_supply/usb/online; sleep 3
kill -0 "$PID" 2>/dev/null && ok "1 s charger blip ignored" || bad "exited on a blip"
press 3 116; waitrc 20; finish; [ "$RC" = 0 ] && ok "then power -> exit 0" || bad "rc $RC"

# 4: ac online alone counts; no frames, or frames for another fb0 -> boot at once, nothing drawn.
setup; echo 1 > sys/class/power_supply/ac/online; echo 0 > sys/class/power_supply/usb/online
start; sleep 5; kill -0 "$PID" 2>/dev/null && grep -q ", ac online: charger power-on$" storage/charge.log \
  && ok "ac online counts" || bad "ac online: $(cat storage/charge.log)"
press 3 116; waitrc 20; finish
for c in "no frames" "stride" "width" "16 bpp"; do
  setup
  case "$c" in
    "no frames") rm -f frames/* ;;
    stride) echo 20 > sys/class/graphics/fb0/stride ;;
    width) echo 5,4 > sys/class/graphics/fb0/virtual_size ;;
    "16 bpp") echo 16 > sys/class/graphics/fb0/bits_per_pixel ;;
  esac
  start; waitrc 20; finish
  [ "$RC" = 0 ] && [ ! -s storage/draw.log ] && [ ! -e storage/vt.log ] && grep -q "no frames for fb0" storage/charge.log \
    && ok "$c -> boot, nothing drawn" || bad "$c -> rc $RC, drew $(cat storage/draw.log 2>/dev/null)"
done

# 6: only a cold plug-in power-on enters: not the power key, a reboot, unread values, or another
# SoC's register; the RK3566 reads its own. (6b: and only with a charger online.)
for c in "power key:0x80:0x00000000:rk3326" "key and plug:0xc0:0x00000000:rk3326" \
         "warm reboot:0x40:0x5242C300:rk3326" "panic reboot:0x40:0x5242C307:rk3326" \
         "no source line::0x00000000:rk3326" "devmem unread:0x40::rk3326" \
         "unknown SoC:0x40:0x00000000:rk3399" "rk3566 warm reboot:0x40:0x5242C300:rk3566"; do
  IFS=: read -r what on mode soc <<< "$c"
  setup; [ -n "$on" ] && echo "[ 1.5] rk808 0-0020: source: on=$on, off=0x08" > fake/dmesg || : > fake/dmesg
  echo "$mode" > fake/devmem; [ -n "$mode" ] || : > fake/devmem
  printf 'vendor,board\0rockchip,%s\0' "$soc" > fake/compatible
  [ "$soc" = rk3566 ] && echo 0xfdc20200 > fake/reg
  start; waitrc 8; finish
  [ "$RC" = 0 ] && [ ! -s storage/draw.log ] && [ ! -e storage/vt.log ] && [ "$(S storage/printk)" = "$(printf '7\t4\t1\t7')" ] \
    && ok "$what -> boot, nothing drawn, console untouched" || bad "$what -> rc $RC, drew $(wc -l < storage/draw.log 2>/dev/null), vt '$(S storage/vt.log)'"
  grep -q "not a charger power-on" storage/charge.log && ok "$what logged" || bad "$what log: $(cat storage/charge.log)"
done
setup; printf 'miniloong,pocket1\0rockchip,rk3566\0' > fake/compatible; echo 0xfdc20200 > fake/reg
start; sleep 4.5
grep -q "on=0x40 boot-mode=0x00000000, usb online: charger power-on" storage/charge.log && ok "rk3566 cold plug-in enters (0xfdc20200)" || bad "rk3566: $(cat storage/charge.log)"
press 3 116; waitrc 20; finish

# 6b: a cold plug-in power-on also needs a charger that stays online for 3 s (a reset that bypasses
# Linux keeps on=0x40 and register 0): none for 4 s -> boot, nothing drawn; one that shows up after 2 s
# enters; one that reads online for 1 s only (the V10 after a reset on battery) or keeps flapping -> boot.
setup; echo 0 > sys/class/power_supply/usb/online
start; sleep 3
kill -0 "$PID" 2>/dev/null && ok "no charger: still waiting at 3 s" || bad "no charger: gave up before 3 s"
waitrc 20; finish
[ "$RC" = 0 ] && [ ! -s storage/draw.log ] && [ ! -e storage/vt.log ] && [ "$(S storage/printk)" = "$(printf '7\t4\t1\t7')" ] \
  && ok "no charger online -> boot, nothing drawn, console untouched" || bad "no charger -> rc $RC, drew $(wc -l < storage/draw.log 2>/dev/null), vt '$(S storage/vt.log)'"
grep -q "no charger online: not a charger power-on" storage/charge.log && ok "no charger logged" || bad "no charger log: $(cat storage/charge.log)"
setup; echo 0 > sys/class/power_supply/usb/online
start; sleep 2; echo 1 > sys/class/power_supply/usb/online; sleep 2
[ ! -s storage/draw.log ] && ok "a charger online for 2 s: nothing drawn yet" || bad "drew after 2 s online: $(cat storage/draw.log)"
sleep 2.5
grep -q ": charger power-on$" storage/charge.log && [ "$(head -1 storage/draw.log)" = "-c /frames/level-040.raw.gz" ] \
  && ok "a charger online after 2 s still enters" || bad "late charger: $(cat storage/charge.log)"
press 3 116; waitrc 20; finish
[ "$RC" = 0 ] && ok "then power -> exit 0" || bad "rc $RC"
setup
start; sleep 1.2; echo 0 > sys/class/power_supply/usb/online; waitrc 32; finish
[ "$RC" = 0 ] && [ ! -s storage/draw.log ] && [ ! -e storage/vt.log ] && [ "$(S storage/printk)" = "$(printf '7\t4\t1\t7')" ] \
  && ok "online for 1 s only -> boot, nothing drawn, console untouched" || bad "brief charger -> rc $RC, drew $(wc -l < storage/draw.log 2>/dev/null), vt '$(S storage/vt.log)'"
grep -q ", usb online only briefly: not a charger power-on$" storage/charge.log && ok "brief charger logged" || bad "brief charger log: $(cat storage/charge.log)"
setup
start; (cd "$T/root" && for _ in 1 2 3 4 5 6 7; do sleep 1; echo 0 > sys/class/power_supply/usb/online; sleep 1; echo 1 > sys/class/power_supply/usb/online; done) &
FLAP=$!; sleep 8
kill -0 "$PID" 2>/dev/null && [ ! -s storage/draw.log ] && ok "flapping charger: still waiting at 8 s, nothing drawn" || bad "flapping: gone or drew before 8 s: $(cat storage/charge.log)"
waitrc 20; finish; kill "$FLAP" 2>/dev/null; wait "$FLAP" 2>/dev/null
[ "$RC" = 0 ] && [ ! -s storage/draw.log ] && grep -q ", usb online only briefly: not a charger power-on$" storage/charge.log \
  && ok "flapping charger -> boot after 10 s, nothing drawn" || bad "flapping -> rc $RC, $(cat storage/charge.log)"

setup; echo "[ 1.5] rk808 0-0020: source: on=0x80, off=0x08" > fake/dmesg
for i in $(seq 1 1500); do echo "old line $i of the boot log, padded to grow past the cap"; done > storage/charge.log
start; waitrc 8; finish
[ "$(wc -l < storage/charge.log)" -le 201 ] && tail -1 storage/charge.log | grep -q "power-on" \
  && ok "log over 64 KB cut to its last 200 lines" || bad "log now $(wc -lc < storage/charge.log)"

# 7: the initramfs hook: exit 2 unmounts the root and powers off; anything else carries on.
hook() {   # hook RC: run darkmoss-charge with a charge-mode.sh stub that exits RC
  rm -rf "$T/hook"; mkdir -p "$T/hook/root/usr/local/lib/darkmoss-charge" "$T/hook/bin" "$T/hook/out"
  [ "$1" = none ] || printf '#!/bin/sh\necho "args $* log $CHARGE_MODE_LOG" >> /out/calls\nexit %s\n' "$1" \
    > "$T/hook/root/usr/local/lib/darkmoss-charge/charge-mode.sh"
  for c in sync umount mount poweroff; do printf '#!/bin/sh\necho "%s $*" >> /out/calls\n' "$c" > "$T/hook/bin/$c"; done
  chmod +x "$T/hook/bin/"*; ln -s /usr/bin/busybox "$T/hook/bin/sh"
  bwrap --unshare-all --die-with-parent --ro-bind /usr/lib /usr/lib --symlink usr/lib /lib \
    --ro-bind /usr/bin/busybox /usr/bin/busybox --proc /proc --dev /dev \
    --bind "$T/hook/root" /root --bind "$T/hook/out" /out --ro-bind "$T/hook/bin" /bin \
    --ro-bind "$T/darkmoss-charge" /hook --setenv PATH /bin --setenv rootmnt /root /bin/sh /hook > /dev/null
  HRC=$?; CALLS=$(tr '\n' '|' 2>/dev/null < "$T/hook/out/calls")
}
hook 2
[ "$CALLS" = "args /root/usr/local/share/darkmoss-charge log /root/var/log/darkmoss-charge.log|sync |umount /root|poweroff -f|" ] \
  && ok "hook: exit 2 -> sync, umount the root, poweroff -f" || bad "hook exit 2: $CALLS"
hook 0; [ "$HRC" = 0 ] && [ "$CALLS" = "args /root/usr/local/share/darkmoss-charge log /root/var/log/darkmoss-charge.log|" ] \
  && ok "hook: exit 0 -> boot on" || bad "hook exit 0: rc $HRC, $CALLS"
hook none; [ "$HRC" = 0 ] && [ -z "$CALLS" ] && ok "hook: no charge-mode.sh -> boot on" || bad "hook none: rc $HRC, $CALLS"

# 8: a unit with two panels: the set for fb0's width (w<width>/), not another width's.
setup; mkdir frames/w4 frames/w9; mv frames/*.gz frames/fb frames/w4/; cp frames/w4/* frames/w9/
start; sleep 5
press 3 116; waitrc 20; finish
[ "$(head -1 storage/draw.log)" = "-c /frames/w4/level-040.raw.gz" ] && [ "$(tail -1 storage/draw.log)" = "-c /frames/w4/booting.raw.gz" ] \
  && ok "two panels: fb0's width picks w4/" || bad "two panels: $(tr '\n' ' ' < storage/draw.log)"
setup; mkdir frames/w9; mv frames/*.gz frames/fb frames/w9/
start; waitrc 20; finish
[ "$RC" = 0 ] && [ ! -s storage/draw.log ] && grep -q "no frames for fb0" storage/charge.log \
  && ok "two panels, neither this width -> boot, nothing drawn" || bad "w9 only: rc $RC, $(cat storage/charge.log)"

# 9: no power key after 5 s: boot (nothing else could), the boot logo drawn, console given back.
setup; echo "rk817 charger" > sys/class/input/event0/device/name; echo 0 > sys/class/input/event0/device/capabilities/key
start; waitrc 52; finish
[ "$RC" = 0 ] && grep -q "no power key; booting" storage/charge.log && [ "$(tail -1 storage/draw.log)" = "-c /frames/booting.raw.gz" ] \
  && [ "$(S storage/vt.log | tr '\n' ' ')" = "2 1 " ] && [ "$(S storage/printk)" = 7 ] \
  && ok "no power key -> boot logo, exit 0, console back" || bad "no power key: rc $RC, $(tail -1 storage/charge.log)"

# 10: CHARGE_MODE_TMP holds the key readers' files, removed on the way out.
setup; mkdir storage/run; ENV=(--setenv CHARGE_MODE_TMP /storage/run); start; sleep 5
[ -e storage/run/charge-pek ] && [ -e storage/run/charge-pad ] && ok "readers' files in CHARGE_MODE_TMP" || bad "run: $(ls storage/run)"
press 3 116; waitrc 20; finish; ENV=()
[ "$RC" = 0 ] && [ -z "$(ls storage/run)" ] && ok "and removed on boot" || bad "rc $RC, left $(ls storage/run)"

# 11: init-charge (no initramfs): mounts what is missing, runs charge-mode.sh with busybox's applets
# first, unmounts and execs /sbin/init with the kernel's arguments; exit 2 powers off.
initc() {   # initc RC: init-charge with a charge-mode.sh stub that exits RC (none: no stub)
  rm -rf "$T/ic"; mkdir -p "$T/ic/r/usr/local/lib/darkmoss-charge" "$T/ic/r/sbin" "$T/ic/r/run" "$T/ic/r/proc" \
    "$T/ic/r/sys" "$T/ic/out"
  [ "$1" = none ] || printf '#!/bin/sh\necho "args $* tmp $CHARGE_MODE_TMP log $CHARGE_MODE_LOG devmem $(command -v devmem)" >> /out/calls\nexit %s\n' "$1" \
    > "$T/ic/r/usr/local/lib/darkmoss-charge/charge-mode.sh"
  printf '#!/usr/bin/busybox sh\necho "init $*" >> /out/calls\n' > "$T/ic/r/sbin/init"
  # busybox, but mount, umount, sync and poweroff only logged, and nothing mounted yet
  printf '#!/usr/bin/busybox sh\ncase "$1" in mount|umount|sync|poweroff) echo "$*" >> /out/calls; exit 0 ;; mountpoint) exit 1 ;; esac\nexec /usr/bin/busybox "$@"\n' \
    > "$T/ic/bb"
  chmod +x "$T/ic/bb" "$T/ic/r/sbin/init"
  bwrap --unshare-all --die-with-parent --ro-bind /usr/lib /usr/lib --symlink usr/lib /lib \
    --ro-bind /usr/bin/busybox /usr/bin/busybox --proc /proc --dev /dev \
    --bind "$T/ic/r" /r --bind "$T/ic/out" /out --ro-bind "$T/ic/bb" /bb --ro-bind "$T/init-charge" /init-charge \
    --setenv CHARGE_MODE_ROOT /r --setenv CHARGE_MODE_BUSYBOX /bb /usr/bin/busybox sh /init-charge quiet splash > /dev/null
  IRC=$?; CALLS=$(tr '\n' '|' 2>/dev/null < "$T/ic/out/calls")
}
M="mount -t proc proc /r/proc|mount -t sysfs sysfs /r/sys|mount -t tmpfs tmpfs /r/run|"
A="args /r/usr/local/share/darkmoss-charge tmp /r/run/darkmoss-charge log /r/var/log/darkmoss-charge.log devmem /r/run/darkmoss-charge/bin/devmem|"
initc 0
[ "$IRC" = 0 ] && [ "$CALLS" = "$M${A}umount /r/run|umount /r/sys|umount /r/proc|init quiet splash|" ] && [ ! -e "$T/ic/r/run/darkmoss-charge" ] \
  && ok "init-charge: exit 0 -> unmount, exec /sbin/init with its arguments" || bad "init-charge 0: rc $IRC, $CALLS"
initc 2
case "$CALLS" in "$M${A}sync|mount -o remount,ro /r/|poweroff -f|"*) ok "init-charge: exit 2 -> sync, root read-only, poweroff -f" ;;
  *) bad "init-charge 2: $CALLS" ;; esac
initc none
[ "$IRC" = 0 ] && [ "$CALLS" = "init quiet splash|" ] && ok "init-charge: no charge-mode.sh -> straight to /sbin/init" || bad "init-charge none: rc $IRC, $CALLS"

# 5: dark after 30 s; the joypad with sticks does not wake it, a pad press does; the power key
# while dark only wakes; power then boots.
if [ "${1:-}" != quick ]; then
  setup; start; sleep 5.5
  sleep 30
  [ "$(S sys/class/graphics/fb0/blank)" = 4 ] && ok "blank after 30 s" || bad "blank=$(S sys/class/graphics/fb0/blank)"
  press 5 304; sleep 1
  [ "$(S sys/class/graphics/fb0/blank)" = 4 ] && ok "joypad with sticks does not wake" || bad "woken by the joypad"
  press 4 115; sleep 1
  [ "$(S sys/class/graphics/fb0/blank)" = 0 ] && ok "pad press wakes" || bad "after pad: blank=$(S sys/class/graphics/fb0/blank)"
  [ "$(tail -1 storage/draw.log)" = "-c /frames/level-040.raw.gz" ] && ok "frame redrawn on wake" || bad "after wake: $(tail -1 storage/draw.log)"
  sleep 31
  [ "$(S sys/class/graphics/fb0/blank)" = 4 ] && ok "dark again" || bad "blank=$(S sys/class/graphics/fb0/blank)"
  press 3 116; sleep 1
  kill -0 "$PID" 2>/dev/null && [ "$(S sys/class/graphics/fb0/blank)" = 0 ] && ok "power while dark only wakes" || bad "power while dark: blank=$(S sys/class/graphics/fb0/blank)"
  press 3 116; waitrc 20; finish
  [ "$RC" = 0 ] && ok "then power -> exit 0" || bad "rc $RC"
fi

echo "$fails failure(s)"
[ "$fails" = 0 ]
