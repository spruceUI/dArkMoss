#!/bin/sh
# This unit's own SSH host keys, made before sshd first needs them. The image
# ships none; earlier images baked in one set that every unit shared, which is
# replaced once, the first time SSH starts after the update that brings this.

MARK=/var/lib/darkmoss/ssh-host-keys

if [ ! -e "$MARK" ]; then
    echo "darkmoss-ssh-hostkeys: replacing any host keys the image brought"
    rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
fi

# Makes only the key types that are missing.
ssh-keygen -A || exit 1
mkdir -p "${MARK%/*}" && date -Iseconds > "$MARK"
sync
