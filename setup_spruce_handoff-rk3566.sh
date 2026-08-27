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

# The spruce SSH account, baked into the image.
#
# Every other spruce device offers the same login - user "spruce", password
# "happygaming", root-equivalent - and the Network Settings screen prints
# exactly that. On the other platforms spruce fabricates it at boot by
# bind-mounting an augmented /etc/passwd and /etc/shadow over the base image's,
# because it does not own those images. Here it does, so create the account
# properly and delete the hack from RGB30.sh.
#
# Two things the bind-mount version could not fix from outside:
#
#   Debian's sshd defaults to PermitRootLogin prohibit-password, so a uid 0
#   account is refused a password login however correct the password is. The
#   failure surfaces as a plain pam_unix authentication failure, which sends
#   you looking at the hash rather than at the policy.
#
#   Its home was /storage, a JELOS path that does not exist on Debian, so even
#   a successful login landed on "Could not chdir to home directory".
echo -e "Creating the spruce SSH account...\n\n"

sudo chroot Arkbuild/ bash -c '
    set -e

    if ! grep -q "^spruce:" /etc/passwd; then
        # uid 0 with its own name: root-equivalent, matching the rest of the
        # fleet, but distinguishable from root in the auth log.
        useradd -o -u 0 -g 0 -M -d /root -s /bin/bash spruce
    fi

    echo "spruce:happygaming" | chpasswd

    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/10-spruce.conf <<EOF
# spruce ships a documented root-equivalent login and the UI tells people to
# use it, so password auth for uid 0 has to be allowed. This is a handheld on
# a home network, not a server.
PermitRootLogin yes
PasswordAuthentication yes
EOF

    # dArkOS ships SSH off and expects its Remote Services tool to turn it on.
    # spruce manages it from Network Settings instead, so have the unit present
    # and disabled rather than absent - starting it is then a systemctl call
    # with no key generation or first-run surprise.
    systemctl disable ssh.service 2>/dev/null || true
    ssh-keygen -A >/dev/null 2>&1 || true

    # spruce toggles SSH with "systemctl start sshd", the name every other
    # platform it supports uses. Debian calls the unit ssh.service and ships no
    # alias, so provide one here rather than teaching spruce a per-distro name.
    ln -sf /lib/systemd/system/ssh.service /etc/systemd/system/sshd.service
'

# Stamp an identifier spruce's platform detection keys off. The RGB30 shares its
# cpuinfo signature (0xd05) with the Miyoo Flip, so spruce reads os-release to
# tell them apart. spruce's helperFunctions.sh must match DARKMOSS in its 0xd05
# case.
if ! grep -q '^OS_NAME=' Arkbuild/etc/os-release 2>/dev/null; then
  echo 'OS_NAME="DARKMOSS"' | sudo tee -a Arkbuild/etc/os-release >/dev/null
fi
