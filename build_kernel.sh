#!/bin/bash

# rk3326 units: the Rockchip BSP 5.10 kernel from arkos4clone (g29p1 Mali, Vulkan), see utils.sh.
# rgb10/rk2020 (upstream units dArkMoss does not build): christianhaitian/linux 4.4.
if [ "$KERNEL_SERIES" == "5.10" ]; then
  KERNEL_SRC="rockchip-5.10"
  KERNEL_510_REPO="https://github.com/jokubasver/rockchip-kernel.git"
  KERNEL_510_COMMIT="453c71de20c0bc736496fc5807dce31461cfc7b4"
  DEF_CONFIG="clone_defconfig"
  # Portrait panels, as on 4.4: none of the 5.10 dts rotate the panel themselves.
  case "$UNIT" in
    xumini)     SCREEN_ROTATION="1" ;;
    v10|rg351p) SCREEN_ROTATION="3" ;;
    *)          SCREEN_ROTATION="0" ;;
  esac
  # V10: the 5.10 tree's Powkiddy RGBV10 dts (same panel, buttons and no sticks as the
  # OGA 1.1 dts it booted on 4.4). xumini: ours, patches/xumini/kernel-5.10.
  KERNEL_DTB="${CHIPSET}-${UNIT}-linux.dtb"
  [ "$UNIT" == "v10" ] && KERNEL_DTB="${CHIPSET}-rgbv10-linux.dtb"
  # Ubuntu's cross gcc by path: the Linaro 6.3 first on PATH stays with the 4.4 kernels.
  if [ ! -x /usr/bin/aarch64-linux-gnu-gcc ]; then
    sudo apt -y install gcc-aarch64-linux-gnu
    verify_action
  fi
  KERNEL_CROSS=/usr/bin/aarch64-linux-gnu-
elif [ "$UNIT" == "rgb10" ] || [ "$UNIT" == "rk2020" ]; then
  KERNEL_SRC="odroidgoA-4.4.y"
  DEF_CONFIG="odroidgoa_tweaked_defconfig"
  SCREEN_ROTATION="3"
  if [ "$UNIT" == "rgb10" ]; then
    KERNEL_DTB="${CHIPSET}-odroidgo2-linux-v11.dtb"
    KERNEL_DTB_ALT="${CHIPSET}-odroidgo2-linux-v11-alt.dtb"
    KERNEL_DTB_RGB10S="${CHIPSET}-odroidgo2-linux-v11-rgb10s.dtb"
  else
    KERNEL_DTB="${CHIPSET}-odroidgo2-linux.dtb"
  fi
else
  KERNEL_SRC="rg351"
  DEF_CONFIG="rg351p_tweaked_defconfig"
  if [ "$UNIT" == "xumini" ]; then
    SCREEN_ROTATION="1"
  elif [ "$UNIT" == "v10" ] || [ "$UNIT" == "rg351p" ]; then
    # 320x480 portrait panel, as the OGA kernel boots it (rgb10 above). The
    # RG351P's panel is the same 320x480 portrait one.
    SCREEN_ROTATION="3"
  else
    SCREEN_ROTATION="0"
  fi
  # RG351P: rk3326-rg351p-linux.dtb from rg351 itself. Not the V10's OGA 1.1
  # dtb: that one holds GPIO0_B7 high as an always-on USB host supply, and on
  # the RG351P GPIO0_B7 is the rumble motor (pwm0), so the motor ran nonstop.
  KERNEL_DTB="${CHIPSET}-${UNIT}-linux.dtb"
  # V10: no dts of its own; rg351 carries the OGA 1.1 one dArkOS boots it with.
  [ "$UNIT" == "v10" ] && KERNEL_DTB="${CHIPSET}-odroidgo2-linux-v11.dtb"
fi
if [ "$KERNEL_SERIES" == "5.10" ] && [ ! -d "$KERNEL_SRC" ]; then
  git init -q $KERNEL_SRC &&
    git -C $KERNEL_SRC fetch -q --depth=1 $KERNEL_510_REPO $KERNEL_510_COMMIT &&
    git -C $KERNEL_SRC checkout -q FETCH_HEAD
  verify_action
elif [ ! -d "$KERNEL_SRC" ]; then
  git clone --recursive --depth=1 https://github.com/christianhaitian/linux.git -b $KERNEL_SRC $KERNEL_SRC
fi
if [ "$KERNEL_SERIES" == "4.4" ] && [ "$UNIT" == "xumini" ] && [ ! -f "$KERNEL_SRC/arch/arm64/boot/dts/rockchip/rk3326-xumini-linux.dts" ]; then
  # Temporary: christianhaitian/linux's rg351 has no xumini unit of its own
  # yet. This is a plain 3-patch series (DTS, xu10-joypad driver, defconfig
  # line) meant to git-am cleanly onto rg351 as-is; drop this whole block
  # for a one-line change if rg351 ever carries the board itself.
  # Absolute path: the shell expands the glob from here, not from $KERNEL_SRC.
  git -C $KERNEL_SRC -c user.name=dArkMoss -c user.email=dArkMoss@localhost \
    am "$PWD"/patches/xumini/kernel/series/*.patch
  test -f "$KERNEL_SRC/arch/arm64/boot/dts/rockchip/rk3326-xumini-linux.dts"
  verify_action
fi
cd $KERNEL_SRC
for patch in ../scripts/kernel-${KERNEL_SRC}/*.patch; do
  [ -e "$patch" ] || continue
  git apply -R --check "$patch" 2>/dev/null && continue
  if ! git apply "$patch"; then
    echo "ERROR: $patch did not apply."
    exit 1
  fi
done
# Opt-in fixes from patches/rk3326/kernel: a unit lists only what it was tested with.
# They and the per-unit patches below are 4.4 patches; on 5.10 a unit's own fixes are
# in patches/<unit>/kernel-5.10.
[ "$KERNEL_SERIES" == "5.10" ] && UNIT_PATCHES=n || UNIT_PATCHES=y
if [ "$KERNEL_SERIES" == "5.10" ]; then
  for fix in ../patches/${UNIT}/kernel-5.10/*.patch; do
    [ -e "$fix" ] || continue
    git apply -R --check "$fix" 2>/dev/null && continue
    git apply "$fix"
    verify_action
  done
fi
case "$UNIT" in
  a10mini) KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  g350)   KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  v10)    KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  rg351p) KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  xumini) KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity rk817-plugin-online" ;;
  *)      KERNEL_OPTIN="" ;;
esac
[ "$UNIT_PATCHES" == "y" ] || KERNEL_OPTIN=""
for fix in $KERNEL_OPTIN; do
  git apply -R --check "../patches/rk3326/kernel/${fix}.patch" 2>/dev/null && continue
  git apply "../patches/rk3326/kernel/${fix}.patch"
  verify_action
done
# G350 board values from BatleXP's own device tree (common/dev-resources/g350).
if [ "$UNIT" == "g350" ] && [ "$UNIT_PATCHES" == "y" ]; then
  for fix in ../patches/g350/kernel/*.patch; do
    git apply -R --check "$fix" 2>/dev/null && continue
    git apply "$fix"
    verify_action
  done
fi
# A10 Mini and V4: 60 Hz panel timing, 3.3 V SD card power.
if [ "$UNIT" == "a10mini" ] && [ "$UNIT_PATCHES" == "y" ]; then
  for fix in ../patches/a10mini/kernel/*.patch; do
    git apply -R --check "$fix" 2>/dev/null && continue
    git apply "$fix"
    verify_action
  done
fi
make ARCH=arm64 ${KERNEL_CROSS:+CROSS_COMPILE=$KERNEL_CROSS} ${DEF_CONFIG}
# FunctionFS for adbd's USB gadget.
scripts/config --enable USB_CONFIGFS_F_FS
make ARCH=arm64 ${KERNEL_CROSS:+CROSS_COMPILE=$KERNEL_CROSS} olddefconfig
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=${KERNEL_CROSS:-aarch64-linux-gnu-} modules_prepare
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=${KERNEL_CROSS:-aarch64-linux-gnu-} Image dtbs modules
verify_action
cd ..

# Install kernel modules
sudo make -C $KERNEL_SRC ARCH=arm64 CROSS_COMPILE=${KERNEL_CROSS:-aarch64-linux-gnu-} INSTALL_MOD_PATH=../Arkbuild modules_install

# Format boot partition
BOOT_PART_OFFSET=$((SYSTEM_PART_START * 512))
BOOT_PART_SIZE=$(( (SYSTEM_PART_END - SYSTEM_PART_START + 1) * 512 ))
LOOP_BOOT=$(sudo losetup --find --show --offset ${BOOT_PART_OFFSET} --sizelimit ${BOOT_PART_SIZE} ${DISK})
sudo mkfs.vfat -F 32 -n BOOT ${LOOP_BOOT}
mountpoint="mnt/boot"
mkdir -p ${mountpoint}
sudo mount ${LOOP_BOOT} ${mountpoint}

# Copy kernel, device tree, and modules into target rootfs
KERNEL_VERSION=$(basename $(ls Arkbuild/lib/modules))
sudo cp $KERNEL_SRC/.config Arkbuild/boot/config-${KERNEL_VERSION}
sudo cp $KERNEL_SRC/arch/arm64/boot/Image ${mountpoint}/
sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB} ${mountpoint}/
# The V4's dtb, which boot.ini loads when U-Boot picked the V4 panel.
[ "$UNIT" == "a10mini" ] && sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${CHIPSET}-a10mini-v4-linux.dtb ${mountpoint}/
# 5.10 needs neither: the RGBV10 dts has no Wi-Fi node, and 5.10's _mmc_sd_shutdown always
# sets the card back to 3.3 V.
if [ "$UNIT" == "v10" ] && [ "$KERNEL_SERIES" == "4.4" ]; then
  # The v11 dts names an ESP8089 SDIO Wi-Fi chip the V10 does not have. With
  # this kernel's rkwifi (WL_ROCKCHIP) that node registers a Wi-Fi power switch,
  # and turning Wi-Fi on froze the V10. Its Wi-Fi is a USB dongle, so the node
  # goes (tested on a V10: no freeze, dongle connects).
  if ! command -v fdtput &> /dev/null; then
    sudo apt -y update
    sudo apt -y install device-tree-compiler
  fi
  sudo fdtput -t s ${mountpoint}/${KERNEL_DTB} /wireless-wlan status disabled
  # The SD card runs at 1.8 V (SDR104); on a reboot the V10's U-Boot then failed to read it. With
  # supports-emmc the kernel sets it back to 3.3 V at shutdown (sd.c _mmc_sd_shutdown; tested on a V10).
  sudo fdtput ${mountpoint}/${KERNEL_DTB} /dwmmc@ff370000 supports-emmc
  verify_action
fi
source scripts/charge-mode/install.sh
if [[ " $UBOOT_OPTIN " == *" uboot-dtb "* ]]; then
  # image_setup.sh's opt-in: U-Boot loads only uboot.dtb, so that is the one U-Boot
  # dtb on BOOT; every unit's dts stays in the U-Boot tree.
  sudo cp /tmp/${UNIT}-uboot.dtb ${mountpoint}/uboot.dtb
  sudo rm /tmp/${UNIT}-uboot.dtb
  if [ "$CHARGE_MODE" == "y" ]; then
    sudo fdtput -t u ${mountpoint}/uboot.dtb /charge-animation rockchip,uboot-charge-on 0
    verify_action
  fi
elif [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "a10mini" ]; then
  sudo cp /tmp/${UNIT}-uboot.dtb ${mountpoint}/rg351mp-uboot.dtb
  sudo rm /tmp/${UNIT}-uboot.dtb
  if [ "$CHARGE_MODE" == "y" ]; then
    sudo fdtput -t u ${mountpoint}/rg351mp-uboot.dtb /charge-animation rockchip,uboot-charge-on 0
    verify_action
  fi
elif [ "$UNIT" == "rgb10" ]; then
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB_ALT} ${mountpoint}/rk3326-odroidgo2-linux-v11.dtb.oga11
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB_RGB10S} ${mountpoint}/rk3326-odroidgo2-linux-v11.dtb.rgb10s
fi
# V10: U-Boot reads its charge animation's dtb from the SPI flash, which no image writes. A
# "manufacture" file on BOOT makes the board code skip the animation (u-boot-rk3326 odroidgoa.c).
if [ "$UNIT" == "v10" ] && [ "$CHARGE_MODE" == "y" ]; then
  echo "dArkMoss charge mode: U-Boot skips its own charge animation while this file is here." |
    sudo tee ${mountpoint}/manufacture > /dev/null
  verify_action
fi

# The G350/Mini M "Loading..." hook is gone; a cached chroot may still carry it.
sudo rm -f Arkbuild/etc/initramfs-tools/scripts/init-top/darkmoss-loading
# Create uInitrd from generated initramfs
sudo cp /usr/bin/qemu-aarch64-static Arkbuild/usr/bin/
KERNEL_VERSION=$(basename $(find Arkbuild/lib/modules -maxdepth 1 -mindepth 1 -type d))
# Create symlink so depmod/initramfs can find modules for uname -r (host kernel)
sudo touch Arkbuild/lib/modules/${KERNEL_VERSION}/modules.builtin.modinfo
call_chroot "uname() { echo ${KERNEL_VERSION}; }; export -f uname; depmod ${KERNEL_VERSION}; update-initramfs -c -k ${KERNEL_VERSION}"
sudo rm Arkbuild/usr/bin/qemu-aarch64-static
sudo cp Arkbuild/boot/initrd.img-* ${mountpoint}/initrd.img
if ! command -v mkimage &> /dev/null; then
  sudo apt -y update
  sudo apt -y install u-boot-tools
fi
sudo mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d ${mountpoint}/initrd.img ${mountpoint}/uInitrd
sudo rm -f ${mountpoint}/initrd.img
