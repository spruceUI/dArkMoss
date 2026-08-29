#!/bin/bash

# Create extlinux.conf
sudo mkdir -p ${mountpoint}/extlinux

if [[ "$UNIT" == "miniloong" ]]; then
  ROTATE_HZ=" panel_miniloong_pocket1.preferred_refresh_hz=60 fbcon=rotate:3"
else
  ROTATE_HZ=""
fi

cat <<EOF | sudo tee ${mountpoint}/extlinux/extlinux.conf
LABEL ArkOS
  LINUX /Image
  FDT /${UNIT_DTB}.dtb
  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootwait rw fsck.repair=yes quiet splash vt.global_cursor_default=0 net.ifnames=0${ROTATE_HZ} console=tty1 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60
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
if [[ "$UNIT" == *"353"* ]] || [[ "$UNIT" == *"503"* ]]; then
  NAME="rg${UNIT}"
else
  NAME="${UNIT}"
fi
echo "$NAME" | sudo tee Arkbuild/etc/hostname
echo -e "# This host address\n127.0.1.1\t${NAME}" | sudo tee -a Arkbuild/etc/hosts
#sudo sed -i "0,/localhost/s//localhost ${NAME}/1" Arkbuild/etc/hosts

# Copy the necessary .asoundrc file for proper audio in emulationstation and emulators
if [[ "$UNIT" == "353v" ]] || [[ "$UNIT" == "rgb20pro" ]]; then
  sudo cp scripts/.asoundbackup/.asoundrcbak.rg353v Arkbuild/home/ark/.asoundrc
  sudo cp scripts/.asoundbackup/.asoundrcbak.rg353v Arkbuild/home/ark/.asoundrcbak
else
  sudo cp audio/.asoundrc.${CHIPSET} Arkbuild/home/ark/.asoundrc
  sudo cp audio/.asoundrcbak.${CHIPSET} Arkbuild/home/ark/.asoundrcbak
fi
sudo cp audio/99-hdmi-audio.rules Arkbuild/etc/udev/rules.d/99-hdmi-audio.rules
sudo cp audio/.asoundrchdmi Arkbuild/home/ark/.asoundrchdmi
sudo cp audio/.asoundrcbt.${CHIPSET} Arkbuild/home/ark/.asoundrcbt
sudo cp audio/audio-switch.sh Arkbuild/usr/local/bin/audio-switch.sh
sudo cp audio/headphone-audio-switch.sh Arkbuild/usr/local/bin/headphone-audio-switch.sh
sudo chroot Arkbuild/ bash -c "chown ark:ark /home/ark/.asoundrc*"
sudo chroot Arkbuild/ bash -c "ln -sfv /home/ark/.asoundrc /etc/asound.conf"
sudo chroot Arkbuild/ bash -c "cp -fv /usr/share/alsa/alsa.conf /usr/share/alsa/alsa.conf.mednafen"
sudo chroot Arkbuild/ bash -c "sed -i '/\"\~\/.asoundrc\"/s//\"\~\/.asoundrc.mednafen\"/' /usr/share/alsa/alsa.conf.mednafen"

# Sleep script and set default SuspendState to mem
sudo mkdir -p Arkbuild/usr/lib/systemd/system-sleep
sudo cp scripts/sleep.${CHIPSET} Arkbuild/usr/lib/systemd/system-sleep/sleep
if [[ "$UNIT" == "miniloong" ]]; then
  sudo sed -i '/RestoreSettingsOnWake/a\    \/usr\/local\/bin\/miniloong-led-mode.sh &' Arkbuild/usr/lib/systemd/system-sleep/sleep
fi
sudo chmod 777 Arkbuild/usr/lib/systemd/system-sleep/sleep
sudo sed -i "/SuspendState\=/c\SuspendState\=mem" Arkbuild/etc/systemd/sleep.conf

# Set DRM on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/hdmi-test.sh &\") | crontab -"

# Set performance governor to ondemand on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/perfnorm quiet &\") | crontab -"

# Check for connected headphones on boot
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/headphone-audio-switch.sh &\") | crontab -"

# Find and record panel id on boot (for rg353 devices only)
if [[ "$UNIT" == *"353"* ]]; then
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot dmesg | grep 'panel id' > /home/ark/.config/.panel_info &\") | crontab -"
fi

# Set the default LED mode on boot (for MiniLoong only)
if [[ "$UNIT" == *"miniloong"* ]]; then
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/checkbrightonboot &\") | crontab -"
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/miniloong-led-mode.sh &\") | crontab -"
fi

# Copy necessary tools for expansion of ROOTFS and convert fat32 games partition to exfat on initial boot
sudo cp scripts/expandtoexfat.sh.${CHIPSET} ${mountpoint}/expandtoexfat.sh
sudo cp scripts/firstboot.sh ${mountpoint}/firstboot.sh
sudo cp scripts/firstboot.service Arkbuild/etc/systemd/system/firstboot.service
sudo chroot Arkbuild/ bash -c "systemctl enable firstboot"

# Add hotkeydaemon service and python script
sudo cp hotkeydaemon/killer_daemon.service Arkbuild/etc/systemd/system/killer_daemon.service
sudo cp hotkeydaemon/killer_daemon.py Arkbuild/usr/local/bin/killer_daemon.py
if [[ "$UNIT" == "miniloong" ]]; then
  sudo sed -i "0,/314/s//316/1" Arkbuild/usr/local/bin/killer_daemon.py
fi
sudo chmod 777 Arkbuild/usr/local/bin/killer_daemon.py
sudo chroot Arkbuild/ bash -c "systemctl disable killer_daemon"

# Add amiga script
sudo cp amiga/amiga.sh Arkbuild/usr/local/bin/

#Generate the post-firstboot fstab. No /roms line and no /opt/system/Tools bind:
#there is no EASYROMS partition on this image - see the strip note below.
if [ "$ROOT_FILESYSTEM_FORMAT" == "btrfs" ]; then
  ROOT_FILESYSTEM_MOUNT_OPTIONS="${ROOT_FILESYSTEM_MOUNT_OPTIONS},ssd_spread"
fi
cat <<EOF | sudo tee ${mountpoint}/fstab.exfat
/dev/mmcblk1p4  /  ${ROOT_FILESYSTEM_FORMAT} ${ROOT_FILESYSTEM_MOUNT_OPTIONS} 0 0

/dev/mmcblk1p3 /boot vfat defaults,noatime 0 0
EOF

# Logging README, on the FAT partition because that is the only thing on TF1 a
# user with a card reader and no Linux box can read. The service and the
# journald config that back this are installed in setup_spruce_handoff-rk3566.sh;
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
#sudo mkdir -p Arkbuild/opt/vulkan
#sudo cp misc/rk3566/vulkan/libmali-bifrost-g52-g29p1.so Arkbuild/opt/vulkan/libmali.so
sudo cp misc/rk3566/vulkan/rk_vk.json Arkbuild/usr/share/vulkan/icd.d/rk_vk.json
sudo cp -f misc/rk3566/vulkan/libvulkan.so.1.3.274 Arkbuild/usr/lib/aarch64-linux-gnu/.
sudo cp -f misc/rk3566/vulkan/libmali-hook.so.1.9.0 Arkbuild/usr/lib/aarch64-linux-gnu/.
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libmali-hook.so.1.9.0 /usr/lib/aarch64-linux-gnu/libmali-hook.so.1"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libmali-hook.so.1 /usr/lib/aarch64-linux-gnu/libmali-hook.so"
sudo chroot Arkbuild/ bash -c "rm -f /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1.3.274 /usr/lib/aarch64-linux-gnu/libvulkan.so.1"
sudo chroot Arkbuild/ bash -c "find /usr/lib/aarch64-linux-gnu -type f -name 'libvulkan.so*' -not -name 'libvulkan.so.1.3.274' -delete"
sudo chroot Arkbuild/ bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1 /usr/lib/aarch64-linux-gnu/libvulkan.so"
sudo chown -R ark:ark Arkbuild/opt/vulkan/
sudo cp dArkOS_Tools/*.sh Arkbuild/opt/system/
sudo cp dArkOS_Tools/${CHIPSET}/*.sh Arkbuild/opt/system/Advanced/
sudo cp dArkOS_Tools/${CHIPSET}/"Enable Low Battery Warning".sh Arkbuild/usr/local/bin/
sudo cp dArkOS_Tools/${CHIPSET}/"Disable Low Battery Warning".sh Arkbuild/usr/local/bin/
sudo rm Arkbuild/opt/system/Advanced/"Enable Low Battery Warning".sh
sudo cp dArkOS_Tools/Advanced/*.sh Arkbuild/opt/system/Advanced/
sudo cp scripts/"Enable Quick Mode".sh Arkbuild/opt/system/Advanced/
sudo cp scripts/${CHIPSET}/"Fix Audio".sh Arkbuild/opt/system/Advanced/
sudo cp scripts/"Switch to SD2 for Roms.sh" Arkbuild/opt/system/Advanced/
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

# Add USB DAC Support
echo -e "Generating 20-usb-alsa.rules udev for usb dac support"
echo -e "KERNEL==\"controlC[0-9]*\", DRIVERS==\"usb\", SYMLINK=\"snd/controlC7\"" | sudo tee Arkbuild/etc/udev/rules.d/20-usb-alsa.rules
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/checknswitchforusbdac.sh &\") | crontab -"

# Disable requirement for sudo for setting niceness
echo "ark              -       nice            -20" | sudo tee -a Arkbuild/etc/security/limits.conf

# For MiniLoong Units Only.  Include led control script and systemd
if [[ "$UNIT" == "miniloong" ]]; then
  sudo cp scripts/miniloong/*.service Arkbuild/etc/systemd/system/
  sudo cp scripts/miniloong/*.sh Arkbuild/usr/local/bin/
  sudo chroot Arkbuild/ bash -c "systemctl enable miniloong_led"
fi

# For RGB30 Units Only.  Check for v1 or v2 units and change dtbs due to performance issues.
# Also provide some battery life status indication
if [[ "$UNIT" == "rgb30" ]]; then
  sudo cp scripts/rgb30/*.py Arkbuild/usr/local/bin/
  sudo cp scripts/rgb30/*.service Arkbuild/etc/systemd/system/
  sudo cp scripts/rgb30/*.sh Arkbuild/usr/local/bin/
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/rgb30versioncheck.sh &\") | crontab -"
  sudo chroot Arkbuild/ bash -c "systemctl enable batt_led"
fi

# For RGB20Pro Units Only.  Allows for different LED states
# Also provide some battery life status indication
if [[ "$UNIT" == "rgb20pro" ]]; then
  sudo cp scripts/rgb20pro/*.py Arkbuild/usr/local/bin/
  sudo cp scripts/rgb20pro/*.service Arkbuild/etc/systemd/system/
  sudo cp scripts/rgb20pro/sleep Arkbuild/usr/lib/systemd/system-sleep/sleep
  sudo chmod 777 Arkbuild/usr/lib/systemd/system-sleep/sleep
  sudo chroot Arkbuild/ bash -c "systemctl enable batt_led"
  sudo chroot Arkbuild/ bash -c "systemctl enable charge_led"
  sudo chroot Arkbuild/ bash -c "echo low_power > /home/ark/.config/.PowerLEDSleep"
fi

# Speaker Toggle to set audio output to SPK on boot
sudo mkdir -p Arkbuild/usr/local/bin
sudo cp scripts/spktoggle.sh Arkbuild/usr/local/bin/
sudo chmod 777 Arkbuild/usr/local/bin/spktoggle.sh
if [[ "$UNIT" != "rgb20pro" ]]; then
  sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/spktoggle.sh &\") | crontab -"
else
  sudo sed -i "/\#\!\/bin\/bash/c\\#\!\/bin\/bash\namixer -q sset \'Playback Path\' HP" ${mountpoint}/firstboot.sh
fi
sudo cp scripts/audiostate.service Arkbuild/etc/systemd/system/audiostate.service
sudo chroot Arkbuild/ bash -c "systemctl enable audiostate"

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
sudo cp scripts/${CHIPSET}/* Arkbuild/usr/local/bin/
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
sudo cp scripts/rk3566/shutdowntasks.service Arkbuild/etc/systemd/system/
sudo chroot Arkbuild/ bash -c "(crontab -l 2>/dev/null; echo \"@reboot /usr/local/bin/panel_set.sh RestoreSettings &\") | crontab -"
sudo chroot Arkbuild/ bash -c "systemctl enable shutdowntasks"
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
# spruce is the frontend, it lives on TF2, and emulationstation.service is
# masked - nothing on this image reads /roms. Dropping the lot also takes a
# pile of network fetches out of the build, each of which upstream retries
# forever on failure.
#
# See setup_partition-rk3566.sh (no p5) and scripts/expandtoexfat.sh.rk3566
# (rootfs grow only).
# --- end strip -------------------------------------------------------------

sync
sudo umount -l ${mountpoint}
