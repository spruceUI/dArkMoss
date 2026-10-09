#!/bin/bash

# Create boot.ini
if [ "$UNIT" == "rg351mp" ]; then
  INITRD_LOADERADDRESS="0x01100000"
else
  INITRD_LOADERADDRESS="0x04000000"
fi
cat <<EOF | sudo tee ${mountpoint}/boot.ini
odroidgoa-uboot-config

setenv bootargs "root=/dev/mmcblk0p2 rootwait rw fsck.repair=yes net.ifnames=0 fbcon=rotate:${SCREEN_ROTATION} console=/dev/ttyFIQ0 quiet splash consoleblank=0 vt.global_cursor_default=0"

# Booting
setenv loadaddr "0x02000000"
setenv initrd_loadaddr "${INITRD_LOADERADDRESS}"
setenv dtb_loadaddr "0x01f00000"

load mmc 1:1 \${loadaddr} Image
load mmc 1:1 \${initrd_loadaddr} uInitrd

load mmc 1:1 \${dtb_loadaddr} ${KERNEL_DTB}

booti \${loadaddr} \${initrd_loadaddr} \${dtb_loadaddr}
EOF

sudo cp logos/unrotated/dArkMoss.bmp ${mountpoint}/logo.bmp

if [ -d "optional" ]; then
  if [ ! -z "$(find optional/ -mindepth 1 -maxdepth 1)" ]; then
    sudo cp optional/* ${mountpoint}/
  fi
fi

# Tell systemd to ignore PowerKey presses.  Let the Global Hotkey daemon handle that
echo "HandlePowerKey=ignore" | sudo tee -a Arkbuild/etc/systemd/logind.conf

# Add some important exports to .bashrc for user ark
echo "export PATH=\"\$PATH:/usr/sbin\"" | sudo tee -a Arkbuild/home/ark/.bashrc
sudo chroot Arkbuild/ bash -c "chown ark:ark /home/ark/.bashrc"

# Set the name in the hostname and add it to the hosts file
if [[ "$UNIT" == *"353"* ]] || [[ "$UNIT" == *"503"* ]]; then
  NAME="rg${UNIT}"
else
  NAME="${UNIT}"
fi
echo "$NAME" | sudo tee Arkbuild/etc/hostname
echo -e "# This host address\n127.0.1.1\t${NAME}" | sudo tee -a Arkbuild/etc/hosts

# Copy the necessary .asoundrc file for proper audio in emulationstation and emulators
sudo cp audio/.asoundrc Arkbuild/home/ark/.asoundrc
sudo cp audio/.asoundrcbak Arkbuild/home/ark/.asoundrcbak
sudo chroot Arkbuild/ bash -c "chown ark:ark /home/ark/.asoundrc*"
sudo chroot Arkbuild/ bash -c "ln -sfv /home/ark/.asoundrc /etc/asound.conf"
sudo chroot Arkbuild/ bash -c "cp -fv /usr/share/alsa/alsa.conf /usr/share/alsa/alsa.conf.mednafen"
sudo chroot Arkbuild/ bash -c "sed -i '/\"\~\/.asoundrc\"/s//\"\~\/.asoundrc.mednafen\"/' /usr/share/alsa/alsa.conf.mednafen"
sudo chroot Arkbuild/ bash -c "cp -fv /usr/share/alsa/alsa.conf /usr/share/alsa/alsa.conf.gametank"
sudo chroot Arkbuild/ bash -c "sed -i '/\"\~\/.asoundrc\"/s//\"\~\/.asoundrc.gametank\"/' /usr/share/alsa/alsa.conf.gametank"

# Sleep script
sudo mkdir -p Arkbuild/usr/lib/systemd/system-sleep
sudo cp scripts/sleep.${CHIPSET} Arkbuild/usr/lib/systemd/system-sleep/sleep
sudo chmod 777 Arkbuild/usr/lib/systemd/system-sleep/sleep

# Set performance governor to ondemand on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/perfnorm quiet &\") | crontab -"

# Speaker Toggle to set audio output to SPK on boot
sudo mkdir -p Arkbuild/usr/local/bin
sudo cp scripts/spktoggle.sh Arkbuild/usr/local/bin/
sudo chmod 777 Arkbuild/usr/local/bin/spktoggle.sh
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/spktoggle.sh &\") | crontab -"
sudo cp scripts/audiopath.service Arkbuild/etc/systemd/system/audiopath.service
sudo cp scripts/audiostate.service Arkbuild/etc/systemd/system/audiostate.service
sudo chroot Arkbuild/ bash -c "systemctl enable audiopath"
sudo chroot Arkbuild/ bash -c "systemctl enable audiostate"

# Copy necessary tools for expansion of ROOTFS and convert fat32 games partition to exfat on initial boot
sudo cp scripts/expandtoexfat.sh.${CHIPSET} ${mountpoint}/expandtoexfat.sh
sudo cp scripts/firstboot.sh ${mountpoint}/firstboot.sh
sudo cp scripts/firstboot.service Arkbuild/etc/systemd/system/firstboot.service
sudo chroot Arkbuild/ bash -c "systemctl enable firstboot"

# Add hotkeydaemon service and python script
sudo cp hotkeydaemon/killer_daemon.service Arkbuild/etc/systemd/system/killer_daemon.service
sudo cp hotkeydaemon/killer_daemon.py Arkbuild/usr/local/bin/killer_daemon.py
sudo chmod 777 Arkbuild/usr/local/bin/killer_daemon.py
sudo chroot Arkbuild/ bash -c "systemctl disable killer_daemon"

# Add amiga script
sudo cp amiga/amiga.sh Arkbuild/usr/local/bin/

#Generate the post-firstboot fstab. No /roms line: mount-spruce.sh mounts spruce.
if [ "$ROOT_FILESYSTEM_FORMAT" == "btrfs" ]; then
  ROOT_FILESYSTEM_MOUNT_OPTIONS="${ROOT_FILESYSTEM_MOUNT_OPTIONS},ssd_spread"
fi
cat <<EOF | sudo tee ${mountpoint}/fstab.exfat
/dev/mmcblk0p2 / ${ROOT_FILESYSTEM_FORMAT} ${ROOT_FILESYSTEM_MOUNT_OPTIONS} 0 0

/dev/mmcblk0p1 /boot vfat defaults 0 2
EOF

# Logging README, on the FAT partition because that is the only thing on TF1 a
# user with a card reader and no Linux box can read. The service and the
# journald config that back this are installed in setup_spruce_handoff.sh;
# this is the last point in the build where the boot partition is still
# mounted, so the file has to be written here.
cat <<EOF | sudo tee ${mountpoint}/README-logging.txt >/dev/null
dArkMoss logging
================

To collect logs: create an empty file named "darkmoss-debug" in this folder
(no extension), put the card back in the device and boot it.

Each boot then writes a timestamped folder inside a "logs" folder here,
containing the previous boot's log, this boot's log, dmesg, a system summary,
and spruce's own log if the spruce card was mounted in time. The five most
recent runs are kept.

To stop collecting: delete the "darkmoss-debug" file. The logs folder can be
deleted at any time.

Note: while the "darkmoss-debug" file is present the text console is also left
on the screen, so kernel messages and any panic are visible. Without it the
console is detached and the display belongs to the frontend.
EOF

# Disable getty on tty0 and tty1
sudo chroot Arkbuild/ bash -c "systemctl disable getty@tty0.service getty@tty1.service"

# Disable some other unneeded services
sudo chroot Arkbuild/ bash -c "systemctl disable ModemManager polkit"

# Disable ssh service from automatically starting
sudo chroot Arkbuild/ bash -c "systemctl disable ssh"

# Update Messaage of the Day
sudo cp -f scripts/00-header Arkbuild/etc/update-motd.d/00-header
sudo cp -f scripts/10-help-text Arkbuild/etc/update-motd.d/10-help-text
sudo rm -f Arkbuild/etc/motd
sudo chmod 777 Arkbuild/etc/update-motd.d/*

# Disable some unneeded interfaces in NetworkManager
cat <<EOF | sudo tee -a Arkbuild/etc/NetworkManager/NetworkManager.conf

[device]
wifi.scan-rand-mac-address=no

[keyfile]
unmanaged-devices=interface-name:p2p0;interface-name:ap0
EOF

# Remove requirement of sudo for controlling nmcli
cat <<EOF | sudo tee -a Arkbuild/etc/polkit-1/rules.d/10-networkmanager.rules
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager") == 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF

# Default set timezone to New York
sudo chroot Arkbuild/ bash -c "ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime"

# Fetch older Debian library versions for PortMaster compatibility
source ./fetch_compat_libs.sh

# Various tools available through Options added here
sudo mkdir -p Arkbuild/opt/system/Advanced
sudo cp dArkOS_Tools/*.sh Arkbuild/opt/system/
sudo cp dArkOS_Tools/${CHIPSET}/*.sh Arkbuild/opt/system/Advanced/
sudo cp dArkOS_Tools/Advanced/*.sh Arkbuild/opt/system/Advanced/
sudo cp scripts/"Enable Quick Mode".sh Arkbuild/opt/system/Advanced/
if [[ "$UNIT" == *"rgb10"* ]] || [[ "$UNIT" == "rk2020" ]] || [[ "$UNIT" == *"oga"* ]]; then
  sudo cp dArkOS_Tools/OGA/*.sh Arkbuild/opt/system/Advanced/
else
  sudo cp scripts/Switch* Arkbuild/usr/local/bin/
  sudo cp scripts/"Switch to SD2 for Roms.sh" Arkbuild/opt/system/Advanced/
fi
sudo chroot Arkbuild/ bash -c "chown -R ark:ark /opt"
sudo chmod -R 777 Arkbuild/opt/system/

# Add tool copy game roms for device RGB10
if [[ "$UNIT" == *"rgb10"* ]]; then
  sudo cp dArkOS_Tools/RGB10/*.sh Arkbuild/opt/system/
fi

# Copy performance scripts
sudo cp scripts/perf* Arkbuild/usr/local/bin/

# Add preservation of SDL_VIDEO_EGL_DRIVER to sudoers
cat <<EOF | sudo tee Arkbuild/etc/sudoers.d/ark_preserve_sdl_video_egl_driver
Defaults        env_keep += "SDL_VIDEO_EGL_DRIVER"
EOF
sudo chmod 0440 Arkbuild/etc/sudoers.d/ark_preserve_sdl_video_egl_driver

# Add USB DAC Support
echo -e "Generating 20-usb-alsa.rules udev for usb dac support"
echo -e "KERNEL==\"controlC[0-9]*\", DRIVERS==\"usb\", SYMLINK=\"snd/controlC7\"" | sudo tee Arkbuild/etc/udev/rules.d/20-usb-alsa.rules
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/checknswitchforusbdac.sh &\") | crontab -"

# Fix LEDs on A10 Mini to default to the nice dim blue light while powered on
if [[ "$UNIT" == "a10mini" ]]; then
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/fix_power_led &\") | crontab -"
fi

# Disable requirement for sudo for setting niceness
echo "ark              -       nice            -20" | sudo tee -a Arkbuild/etc/security/limits.conf

# Copy various other backend tools
sudo cp scripts/checkbrightonboot Arkbuild/usr/local/bin/
sudo cp scripts/current_* Arkbuild/usr/local/bin/
sudo cp scripts/finish.sh Arkbuild/usr/local/bin/
sudo cp scripts/pause.sh Arkbuild/usr/local/bin/
sudo cp scripts/finish.sh.qm Arkbuild/usr/local/bin/
sudo cp scripts/pause.sh.qm Arkbuild/usr/local/bin/
sudo cp scripts/finish.sh Arkbuild/usr/local/bin/finish.sh.orig
sudo cp scripts/pause.sh Arkbuild/usr/local/bin/pause.sh.orig
sudo cp scripts/speak_bat_life.sh Arkbuild/usr/local/bin/
sudo cp scripts/spktoggle.sh Arkbuild/usr/local/bin/
sudo cp scripts/timezones Arkbuild/usr/local/bin/
sudo cp scripts/BaRT_QuickMode.sh Arkbuild/usr/local/bin/
sudo cp scripts/"Enable Quick Mode".sh Arkbuild/usr/local/bin/
sudo cp scripts/"Disable Quick Mode".sh Arkbuild/usr/local/bin/
sudo cp scripts/arkos_ap_mode.sh Arkbuild/usr/local/bin/
sudo cp scripts/auto_suspend* Arkbuild/usr/local/bin/
sudo cp scripts/processcheck.sh Arkbuild/usr/local/bin/
sudo cp scripts/autosuspend.service Arkbuild/etc/systemd/system/
sudo chroot Arkbuild/ bash -c "pip install --break-system-packages --root-user-action ignore inputs"
sudo chroot Arkbuild/ bash -c "systemctl disable autosuspend"
sudo cp scripts/wifi_importer.service Arkbuild/etc/systemd/system/
sudo chroot Arkbuild/ bash -c "systemctl enable wifi_importer"
sudo cp scripts/keystroke.py Arkbuild/usr/local/bin/
sudo cp scripts/b2.sh Arkbuild/usr/local/bin/
sudo cp scripts/freej2me.sh Arkbuild/usr/local/bin/
sudo cp scripts/easyrpg.sh Arkbuild/usr/local/bin/
sudo cp scripts/get_last_played.sh Arkbuild/usr/local/bin/
sudo cp scripts/gx4000.sh Arkbuild/usr/local/bin/
sudo cp scripts/isitpng.sh Arkbuild/usr/local/bin/
sudo cp scripts/neogeocd.sh Arkbuild/usr/local/bin/
sudo cp scripts/netplay.sh Arkbuild/usr/local/bin/
sudo mkdir -p Arkbuild/etc/hostapd
sudo cp hostapd/hostapd.conf Arkbuild/etc/hostapd/
sudo cp dnsmasq/dnsmasq.conf Arkbuild/etc/
sudo cp scripts/sleep_governors.sh Arkbuild/usr/local/bin/
sudo cp scripts/wasitpng.sh Arkbuild/usr/local/bin/
sudo cp global/* Arkbuild/usr/local/bin/
# Disable winbind as connectivity to Active Directory is not needed
sudo chroot Arkbuild/ bash -c "systemctl disable winbind"
# Disable samba-ad-dc as connectivity to Active Directory is not needed as well as some other services
sudo chroot Arkbuild/ bash -c "systemctl disable samba-ad-dc dnsmasq hostapd"
# Disable e2scrub_reap if ext file system is not being used for rootfs
if [ "$ROOT_FILESYSTEM_FORMAT" == "xfs" ] || [ "$ROOT_FILESYSTEM_FORMAT" == "btrfs" ]; then
  sudo chroot Arkbuild/ bash -c "systemctl disable e2scrub_reap"
fi
# Set the default graphical target to multi-user instead of graphical"
sudo chroot Arkbuild/ bash -c "systemctl set-default multi-user.target"
if [[ "$UNIT" == "rgb10" ]]; then
  sudo cp device/rgb10/* Arkbuild/usr/local/bin/
elif [[ "$UNIT" == "rg351mp" ]] || [[ "$UNIT" == "g350" ]] || [[ "$UNIT" == "a10mini" ]]; then
  sudo cp device/rg351mp/*.sh Arkbuild/usr/local/bin/
  sudo cp device/rg351mp/*.py Arkbuild/usr/local/bin/
  sudo cp device/rg351mp/*.green Arkbuild/usr/local/bin/
  sudo cp device/rg351mp/*.red Arkbuild/usr/local/bin/
  sudo cp device/rg351mp/fix_power_led Arkbuild/usr/local/bin/
  sudo cp device/rg351mp/checkbrightonboot Arkbuild/usr/local/bin/
  if [[ "$UNIT" == "a10mini" ]]; then
    sudo cp device/a10mini/"Change LED to Green.sh" Arkbuild/opt/system/"Change LED to Orange.sh"
    sudo sed -i '/Green.sh/s//Orange.sh/g' Arkbuild/opt/system/"Change LED to Orange.sh"
	sudo sed -i '/Red.sh/s//Blue.sh/g' Arkbuild/opt/system/"Change LED to Orange.sh"
    sudo cp Arkbuild/opt/system/"Change LED to Orange.sh" Arkbuild/usr/local/bin/"Change LED to Orange.sh"
    sudo rm Arkbuild/usr/local/bin/"Change LED to Green.sh"
    sudo mv -f Arkbuild/usr/local/bin/"Change LED to Red.sh" Arkbuild/usr/local/bin/"Change LED to Blue.sh"
    sudo sed -i '/Red.sh/s//Blue.sh/g' Arkbuild/usr/local/bin/"Change LED to Blue.sh"
	sudo sed -i '/Green.sh/s//Orange.sh/g' Arkbuild/usr/local/bin/"Change LED to Blue.sh"
    sudo chroot Arkbuild/ bash -c "chown -R ark:ark /opt"
    sudo chmod 777 Arkbuild/opt/system/"Change LED to Orange.sh"
  else
    sudo cp device/rg351mp/"Change LED to Red.sh" Arkbuild/opt/system/
    sudo chroot Arkbuild/ bash -c "chown -R ark:ark /opt"
    sudo chmod 777 Arkbuild/opt/system/"Change LED to Red.sh"
  fi
  sudo cp device/rg351mp/*.service Arkbuild/etc/systemd/system/
  sudo chroot Arkbuild/ bash -c "systemctl enable 351mp batt_led"
fi
# No G350 logo.service: it shows /boot/logo.bmp with image-viewer, which is
# not built into dArkMoss.

# Make all scripts in /usr/local/bin executable, world style
sudo chmod 777 Arkbuild/usr/local/bin/*

# Link themes folder to /roms/themes and clone some themes to the folder
sudo rm -rf Arkbuild/etc/emulationstation/themes/
sudo chroot Arkbuild/ bash -c "ln -sfv /roms/themes/ /etc/emulationstation/themes"

# Also expose /roms2/themes via the user themes path so ES picks up themes
# from the second SD card in SD2-for-Roms mode (dangles harmlessly otherwise).
if [[ "$UNIT" != *"rgb10"* ]] && [[ "$UNIT" != "rk2020" ]] && [[ "$UNIT" != *"oga"* ]]; then
  sudo chroot Arkbuild/ bash -c "ln -sfv /roms2/themes/ /home/ark/.emulationstation/themes"
fi

# Link music folder to /roms/bgmusic
sudo rm -rf Arkbuild/home/ark/.emulationstation/music
sudo chroot Arkbuild/ bash -c "ln -sfv /roms/bgmusic/ /home/ark/.emulationstation/music"

# Set launchimage to PIC mode
sudo chroot Arkbuild/ touch /home/ark/.config/.GameLoadingIModePIC

# Set default volume
sudo cp audio/asound.state.${CHIPSET} Arkbuild/var/local/asound.state

# Set SDL Video Driver for bash
echo "export SDL_VIDEO_EGL_DRIVER=libEGL.so" | sudo tee Arkbuild/etc/profile.d/SDL_VIDEO.sh

# Set device name 
dNAME=`echo $NAME | tr '[:lower:]' '[:upper:]'`
echo "$dNAME" | sudo tee Arkbuild/home/ark/.config/.DEVICE

# Configure default samba share setup
cat <<EOF | sudo tee -a Arkbuild/etc/samba/smb.conf
[roms]
   comment = ROMS
   path = /roms
   browsable = yes
   read only = no
   map archive = no
   map system = no
   map hidden = no
   guest ok = yes
   read list = guest

[opt]
   comment = OPT
   path = /opt
   browsable = yes
   read only = no
   map archive = no
   map system = no
   map hidden = no
   guest ok = yes
   read list = guest

[ark]
   comment = ark
   path = /home/ark
   browsable = yes
   read only = no
   map archive = no
   map system = no
   map hidden = no
   guest ok = yes
   read list = guest
EOF
if [[ "$UNIT" != *"rgb10"* ]] && [[ "$UNIT" != "rk2020" ]] && [[ "$UNIT" != *"oga"* ]]; then
  cat <<EOF | sudo tee -a Arkbuild/etc/samba/smb.conf
[roms2]
   comment = ROMS2
   path = /roms2
   browsable = yes
   read only = no
   map archive = no
   map system = no
   map hidden = no
   guest ok = yes
   read list = guest
EOF
  fi

sudo chroot Arkbuild/ bash -c "systemctl disable smbd"
sudo chroot Arkbuild/ bash -c "systemctl disable nmbd"

# Set distro identification and version
sudo mkdir -p Arkbuild/usr/share/plymouth/themes/
cat <<EOF | sudo tee Arkbuild/usr/share/plymouth/themes/text.plymouth
title=dArkMoss (${BUILD_DATE})
EOF
echo "${BUILD_DATE}" | sudo tee Arkbuild/home/ark/.config/.VERSION

# Set boot up welcome text with distro and version
sudo cp scripts/boot_text.sh Arkbuild/usr/local/bin/
sudo chmod 777 Arkbuild/usr/local/bin/boot_text.sh
sudo cp scripts/welcome-message.service Arkbuild/etc/systemd/system/welcome-message.service
sudo chroot Arkbuild/ bash -c "systemctl enable welcome-message"

# Mark completed dArkMoss updates with this current build
release_tags=( $(git -c 'versionsort.suffix=-' ls-remote --tags --sort='v:refname' https://github.com/christianhaitian/darkos-updates.git | cut -d/ -f3- | sed 's/^v//I') )
if [[ ! -z "$release_tags" ]]; then
  for release_tag in "${release_tags[@]}"
  do
    sudo touch Arkbuild/home/ark/.config/.update${release_tag}
  done
fi

# Set the ownver of the ark folder and all sub content to ark
sudo chroot Arkbuild/ bash -c "chown -R ark:ark /home/ark"

# --- dArkMoss strip: no EmulationStation, no EASYROMS ----------------------
# Upstream staged ES themes in /tempthemes here, then below formatted the ROMS
# partition and filled it with an ES ROM tree, PortMaster and ThemeMaster
# installers, pico-8 carts and launch images, tarred into /roms.tar for
# firstboot. spruce is the frontend, so none of it is built.
# See scripts/expandtoexfat.sh.rk3326.
# --- end strip -------------------------------------------------------------

sync
sudo umount -l ${mountpoint}
sudo losetup -d ${LOOP_BOOT}

# Format rootfs partition in final image
ROOTFS_PART_OFFSET=$((STORAGE_PART_START * 512))
LOOP_ROOTFS=$(sudo losetup --find --show --offset ${ROOTFS_PART_OFFSET} ${DISK})
sudo mkfs.${ROOT_FILESYSTEM_FORMAT} ${ROOT_FILESYSTEM_FORMAT_PARAMETERS} ${LOOP_ROOTFS}
sudo losetup -d ${LOOP_ROOTFS}

