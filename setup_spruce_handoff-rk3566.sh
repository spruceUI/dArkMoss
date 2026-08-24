#!/bin/bash
# dArkMoss: hand the boot off to spruce on TF2 instead of EmulationStation.
#
# spruce is the whole frontend and brings its own emulators from TF2, so the ES
# build is stripped out of build_rgb30.sh. This installs a systemd service that,
# once the base system is up, mounts the spruce card (TF2) at /mnt/SDCARD and
# execs spruce's own runtime.sh.

echo -e "Wiring the spruce hand-off...\n\n"

# The TF2 mount helper and the launcher unit.
sudo cp scripts/spruce/mount-spruce.sh Arkbuild/usr/local/sbin/mount-spruce.sh
sudo chmod 0755 Arkbuild/usr/local/sbin/mount-spruce.sh
sudo cp scripts/spruce/spruce-launch.service Arkbuild/etc/systemd/system/spruce-launch.service

# spruce expects the card at /mnt/SDCARD; mount-spruce.sh mounts TF2 there.
sudo mkdir -p Arkbuild/mnt/SDCARD

# EmulationStation is not built into dArkMoss, but mask it defensively so
# nothing can pull it in, and enable our launcher in its place.
sudo chroot Arkbuild/ bash -c "systemctl mask emulationstation.service 2>/dev/null; systemctl enable spruce-launch.service"

# Stamp an identifier spruce's platform detection keys off. The RGB30 shares its
# cpuinfo signature (0xd05) with the Miyoo Flip, so spruce reads os-release to
# tell them apart: MOSSYSPRUCE/MOSS did this on the JELOS base, DARKMOSS does it
# here. spruce's helperFunctions.sh must match DARKMOSS in its 0xd05 case.
if ! grep -q '^OS_NAME=' Arkbuild/etc/os-release 2>/dev/null; then
  echo 'OS_NAME="DARKMOSS"' | sudo tee -a Arkbuild/etc/os-release >/dev/null
fi
