#!/bin/bash

# Create extlinux.conf
sudo mkdir -p ${mountpoint}/extlinux

cat <<EOF | sudo tee ${mountpoint}/extlinux/extlinux.conf
LABEL ArkOS
  LINUX /Image
  FDT /${UNIT_DTB}.dtb
  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootfstype=btrfs rootwait rw fsck.repair=yes quiet splash vt.global_cursor_default=0 net.ifnames=0 fbcon=rotate:1 console=ttyFIQ0,1500000 console=tty1 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60
EOF

#sudo cp logo.bmp ${mountpoint}/
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
NAME="${UNIT}"
echo "$NAME" | sudo tee Arkbuild/etc/hostname
echo -e "# This host address\n127.0.1.1\t${NAME}" | sudo tee -a Arkbuild/etc/hosts
#sudo sed -i "0,/localhost/s//localhost ${NAME}/1" Arkbuild/etc/hosts

# Copy the necessary .asoundrc file for proper audio in emulationstation and emulators
sudo cp audio/.asoundrc.${CHIPSET} Arkbuild/home/ark/.asoundrc
sudo cp audio/.asoundrcbak.${CHIPSET} Arkbuild/home/ark/.asoundrcbak
sudo cp audio/99-hdmi-audio.rules Arkbuild/etc/udev/rules.d/99-hdmi-audio.rules
sudo cp audio/.asoundrchdmi Arkbuild/home/ark/.asoundrchdmi
sudo cp audio/.asoundrcbt.${CHIPSET} Arkbuild/home/ark/.asoundrcbt
sudo cp audio/audio-switch.sh Arkbuild/usr/local/bin/audio-switch.sh
sudo chroot Arkbuild/ bash -c "chown ark:ark /home/ark/.asoundrc*"
sudo chroot Arkbuild/ bash -c "ln -sfv /home/ark/.asoundrc /etc/asound.conf"
sudo chroot Arkbuild/ bash -c "cp -fv /usr/share/alsa/alsa.conf /usr/share/alsa/alsa.conf.mednafen"
sudo chroot Arkbuild/ bash -c "sed -i '/\"\~\/.asoundrc\"/s//\"\~\/.asoundrc.mednafen\"/' /usr/share/alsa/alsa.conf.mednafen"

# Sleep script and set default SuspendState to freeze
sudo mkdir -p Arkbuild/usr/lib/systemd/system-sleep
sudo cp scripts/sleep.${CHIPSET} Arkbuild/usr/lib/systemd/system-sleep/sleep
sudo chmod 777 Arkbuild/usr/lib/systemd/system-sleep/sleep
sudo sed -i "/SuspendState\=/c\SuspendState\=freeze" Arkbuild/etc/systemd/sleep.conf

# Set DRM on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/hdmi-test.sh &\") | crontab -"

# Set performance governor to ondemand on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/perfnorm quiet &\") | crontab -"

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

#Generate the post-firstboot fstab. No /roms line and no /opt/system/Tools bind:
#mount-spruce.sh mounts spruce - see the strip note below.
if [ "$ROOT_FILESYSTEM_FORMAT" == "btrfs" ]; then
  ROOT_FILESYSTEM_MOUNT_OPTIONS="${ROOT_FILESYSTEM_MOUNT_OPTIONS},ssd_spread"
fi
cat <<EOF | sudo tee ${mountpoint}/fstab.exfat
/dev/mmcblk1p4  /  ${ROOT_FILESYSTEM_FORMAT} ${ROOT_FILESYSTEM_MOUNT_OPTIONS} 0 0

/dev/mmcblk1p3 /boot vfat defaults,noatime 0 0
EOF

# Logging README, on the FAT partition because that is the only thing on TF1 a
# user with a card reader and no Linux box can read. The service and the
# journald config that back this are installed in setup_spruce_handoff.sh;
# this is the last point in the build where p3 is still mounted, so the file has
# to be written here.
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
sudo cp misc/rk3566/vulkan/rk_vk.json Arkbuild/usr/share/vulkan/icd.d/rk_vk.json
sudo cp -f misc/rk3566/vulkan/libvulkan.so.1.3.274 Arkbuild/usr/lib/aarch64-linux-gnu/.
sudo cp -f misc/rk3566/vulkan/libmali-hook.so.1.9.0 Arkbuild/usr/lib/aarch64-linux-gnu/.
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libmali-hook.so.1.9.0 /usr/lib/aarch64-linux-gnu/libmali-hook.so.1"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libmali-hook.so.1 /usr/lib/aarch64-linux-gnu/libmali-hook.so"
sudo chroot Arkbuild/ bash -c "rm -f /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1.3.274 /usr/lib/aarch64-linux-gnu/libvulkan.so.1"
sudo chroot Arkbuild/ bash -c "find /usr/lib/aarch64-linux-gnu -type f -name 'libvulkan.so*' -not -name 'libvulkan.so.1.3.274' -delete"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
sudo cp dArkOS_Tools/*.sh Arkbuild/opt/system/
sudo cp dArkOS_Tools/Advanced/*.sh Arkbuild/opt/system/Advanced/
sudo chroot Arkbuild/ bash -c "chown -R ark:ark /opt"
sudo chmod -R 777 Arkbuild/opt/system/

# Copy performance scripts
sudo cp scripts/perf* Arkbuild/usr/local/bin/

# Add preservation of SDL_VIDEO_EGL_DRIVER to sudoers
cat <<EOF | sudo tee Arkbuild/etc/sudoers.d/ark_preserve_sdl_video_egl_driver
Defaults        env_keep += "SDL_VIDEO_EGL_DRIVER"
EOF
sudo chmod 0440 Arkbuild/etc/sudoers.d/ark_preserve_sdl_video_egl_driver

# Disable power saving for 8821cs wifi chip
cat <<EOF | sudo tee Arkbuild/etc/modprobe.d/8821cs.conf
# Disable power saving
options 8821cs rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0
EOF
cat <<EOF | sudo tee Arkbuild/etc/modprobe.d/8723ds.conf
# Disable power saving
options 8723ds rtw_power_mgnt=0 rtw_enusbss=0 rtw_ips_mode=0
EOF

# Add USB DAC Support
echo -e "Generating 20-usb-alsa.rules udev for usb dac support"
echo -e "KERNEL==\"controlC[0-9]*\", DRIVERS==\"usb\", SYMLINK=\"snd/controlC7\"" | sudo tee Arkbuild/etc/udev/rules.d/20-usb-alsa.rules
# dArkMoss: a unit, not a cron @reboot job. cron leaves the loop running when it stops, and the
# loop keeps a deleted file under /tmp open, so /tmp cannot unmount at shutdown.
sudo cp scripts/checknswitchforusbdac.service Arkbuild/etc/systemd/system/checknswitchforusbdac.service
sudo chroot Arkbuild/ bash -c "systemctl enable checknswitchforusbdac.service"

# Disable requirement for sudo for setting niceness
echo "ark              -       nice            -20" | sudo tee -a Arkbuild/etc/security/limits.conf

# RK3562 hardware, from bmdhacks/dArkOS_rg52mini.
# ATF's SYSTEM_OFF resets the board instead of powering it off, so power off
# through the RK817 directly.
sudo cp scripts/rk3562-poweroff.sh Arkbuild/usr/local/bin/rk3562-poweroff.sh
sudo chmod 755 Arkbuild/usr/local/bin/rk3562-poweroff.sh
sudo cp scripts/rk3562-poweroff.service Arkbuild/etc/systemd/system/rk3562-poweroff.service
sudo chroot Arkbuild/ bash -c "systemctl enable rk3562-poweroff"
# Two RG52 Mini revisions: RK915 (rev A) or AIC8800DL (rev B) WiFi. Each driver
# pulses the WiFi power rail at init, so load one: rk915 first, aic8800 if it
# finds no chip. udev must not autoload aic8800 behind its back.
sudo cp scripts/wifi-driver-load.sh Arkbuild/usr/local/bin/wifi-driver-load.sh
sudo chmod 755 Arkbuild/usr/local/bin/wifi-driver-load.sh
sudo cp scripts/wifi-driver-load.service Arkbuild/etc/systemd/system/wifi-driver-load.service
sudo chroot Arkbuild/ bash -c "systemctl enable wifi-driver-load"
sudo install -m 644 scripts/rk3562/modprobe.d/dArkOS-wifi.conf Arkbuild/etc/modprobe.d/dArkOS-wifi.conf
# Fan off when /home/ark/.config/.FAN_DISABLED exists.
sudo install -m 755 scripts/rk3562/fan-state-apply.sh Arkbuild/usr/local/bin/fan-state-apply.sh
sudo install -m 644 scripts/rk3562/fan-state.service Arkbuild/etc/systemd/system/fan-state.service
sudo chroot Arkbuild/ bash -c "systemctl enable fan-state"
# Stick RGB LEDs, through the MCU on /dev/ttyS1. Off until led.cfg exists.
sudo install -m 755 scripts/rk3562/ledctl.sh Arkbuild/usr/local/bin/ledctl
sudo install -m 644 scripts/rk3562/led-state.service Arkbuild/etc/systemd/system/led-state.service
sudo chroot Arkbuild/ bash -c "systemctl enable led-state"
# Mali EGL opens the DMA heaps as the user.
echo 'SUBSYSTEM=="dma_heap", MODE="0666"' | sudo tee Arkbuild/etc/udev/rules.d/99-dma-heap.rules

# Speaker Toggle to set audio output to SPK on boot
sudo mkdir -p Arkbuild/usr/local/bin
sudo cp scripts/spktoggle.sh Arkbuild/usr/local/bin/
sudo chmod 777 Arkbuild/usr/local/bin/spktoggle.sh
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/spktoggle.sh &\") | crontab -"
sudo cp scripts/audiostate.service Arkbuild/etc/systemd/system/audiostate.service
sudo chroot Arkbuild/ bash -c "systemctl enable audiostate"

# Wired adbd
sudo install -D -m 0755 scripts/adbd/adbd-gadget.sh Arkbuild/usr/local/sbin/adbd-gadget.sh
sudo cp scripts/adbd/adbd.service Arkbuild/etc/systemd/system/
sudo chroot Arkbuild/ bash -c "systemctl enable adbd"

# Copy various other backend tools
sudo cp -R scripts/.asoundbackup/ Arkbuild/usr/local/bin/
sudo cp scripts/round_end.wav Arkbuild/usr/local/bin/
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
sudo cp scripts/volume.sh Arkbuild/usr/local/bin/
sudo cp scripts/${CHIPSET}/hdmi-test.sh Arkbuild/usr/local/bin/
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
#sudo cp device/${CHIPSET}/uboot.img.anbernic Arkbuild/usr/local/bin/
sudo cp scripts/Switch* Arkbuild/usr/local/bin/
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

# Make all scripts in /usr/local/bin executable, world style
sudo chmod 777 Arkbuild/usr/local/bin/*

# Link themes folder to /roms/themes and clone some themes to the folder
sudo rm -rf Arkbuild/etc/emulationstation/themes/
sudo chroot Arkbuild/ bash -c "ln -sfv /roms/themes/ /etc/emulationstation/themes"

# Also expose /roms2/themes via the user themes path so ES picks up themes
# from the second SD card in SD2-for-Roms mode (dangles harmlessly otherwise).
sudo chroot Arkbuild/ bash -c "ln -sfv /roms2/themes/ /home/ark/.emulationstation/themes"

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
# Upstream built an ES ROM tree here (game_systems.txt directories, the
# PortMaster and ThemeMaster installers, sample pico-8 carts, launch images,
# scan scripts and eight es-theme-* clones), tarred it into /roms.tar, and
# staged more themes in /tempthemes for firstboot to unpack onto EASYROMS.
#
# spruce is the frontend and emulationstation.service is
# masked - nothing on this image reads /roms. Dropping the lot also takes a
# pile of network fetches out of the build, each of which upstream retries
# forever on failure.
#
# See scripts/expandtoexfat.sh.rk3562.
# --- end strip -------------------------------------------------------------

sync
sudo umount -l ${mountpoint}
