#!/bin/bash

# Build and install custom kernel from christianhaitian/linux
if [ "$UNIT" == "pixel2" ]; then
  # RK3326S (PX30S): 4.4 has no PX30S support, Christian's 5.10 does. Its
  # multi-SoC rk3566 defconfig carries PX30, plus a fragment for USB Wi-Fi.
  KERNEL_SRC="kernel_5_10_226"
  KERNEL_REPO="https://github.com/christianhaitian/kernel_5_10_226.git"
  DEF_CONFIG="rk3566_optimized_linux_defconfig"
  DEF_CONFIG_FRAGMENT="patches/pixel2/kernel/pixel2.config"
  # Mainline gives its panel rotation = <270>, as on the OGA.
  SCREEN_ROTATION="3"
  KERNEL_DTB="rk3326s-gkd-pixel2.dtb"
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
  elif [ "$UNIT" == "v10" ]; then
    # 320x480 portrait panel, as the OGA kernel boots it (rgb10 above).
    SCREEN_ROTATION="3"
  else
    SCREEN_ROTATION="0"
  fi
  KERNEL_DTB="${CHIPSET}-${UNIT}-linux.dtb"
  # V10: no dts of its own; rg351 carries the OGA 1.1 one dArkOS boots it with.
  [ "$UNIT" == "v10" ] && KERNEL_DTB="${CHIPSET}-odroidgo2-linux-v11.dtb"
fi
if [ ! -d "$KERNEL_SRC" ] && [ -n "$KERNEL_REPO" ]; then
  git clone --depth=1 $KERNEL_REPO $KERNEL_SRC
elif [ ! -d "$KERNEL_SRC" ]; then
  git clone --recursive --depth=1 https://github.com/christianhaitian/linux.git -b $KERNEL_SRC $KERNEL_SRC
fi
UNIT_DTS="$KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB%.dtb}.dts"
if [ -d "patches/${UNIT}/kernel/series" ] && [ ! -f "$UNIT_DTS" ]; then
  # Boards Christian's kernels do not carry (xumini on rg351, pixel2 on
  # 5.10): a plain series (DTS, drivers, defconfig) that git-ams cleanly onto
  # the tree as-is; drop a unit's series if the tree ever carries the board.
  # Absolute path: the shell expands the glob from here, not from $KERNEL_SRC.
  git -C $KERNEL_SRC -c user.name=dArkMoss -c user.email=dArkMoss@localhost \
    am "$PWD"/patches/${UNIT}/kernel/series/*.patch
  test -f "$UNIT_DTS"
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
case "$UNIT" in
  g350)   KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  v10)    KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity" ;;
  xumini) KERNEL_OPTIN="no-async-page-flip vt-csi-ignore rk817-gauge-capacity rk817-plugin-online" ;;
  *)      KERNEL_OPTIN="" ;;
esac
for fix in $KERNEL_OPTIN; do
  git apply -R --check "../patches/rk3326/kernel/${fix}.patch" 2>/dev/null && continue
  git apply "../patches/rk3326/kernel/${fix}.patch"
  verify_action
done
# G350 board values from BatleXP's own device tree (common/dev-resources/g350).
if [ "$UNIT" == "g350" ]; then
  for fix in ../patches/g350/kernel/*.patch; do
    git apply -R --check "$fix" 2>/dev/null && continue
    git apply "$fix"
    verify_action
  done
fi
make ARCH=arm64 ${DEF_CONFIG}
if [ -n "$DEF_CONFIG_FRAGMENT" ]; then
  # dArkMoss's 5.10 fixes (build_kernel-rk3566.sh applies the same set).
  for patch in ../scripts/kernel/*.patch; do
    git apply -R --check "$patch" 2>/dev/null && continue
    git apply "$patch"
    verify_action
  done
  ARCH=arm64 scripts/kconfig/merge_config.sh -m .config ../${DEF_CONFIG_FRAGMENT}
  make ARCH=arm64 olddefconfig
  verify_action
fi
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_prepare
CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs modules
verify_action
cd ..

# Install kernel modules
sudo make -C $KERNEL_SRC ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=../Arkbuild modules_install

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
# The PX30S tree (dmc on, Rockchip's PX30S fixups), which boot.ini loads for /darkmoss-px30s.
[ "$UNIT" == "pixel2" ] && sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/rk3326s-gkd-pixel2-px30s.dtb ${mountpoint}/
if [[ " $UBOOT_OPTIN " == *" uboot-dtb "* ]]; then
  # image_setup.sh's opt-in: U-Boot loads only uboot.dtb, so that is the one U-Boot
  # dtb on BOOT; every unit's dts stays in the U-Boot tree.
  sudo cp /tmp/${UNIT}-uboot.dtb ${mountpoint}/uboot.dtb
  sudo rm /tmp/${UNIT}-uboot.dtb
elif [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "a10mini" ]; then
  sudo cp /tmp/${UNIT}-uboot.dtb ${mountpoint}/rg351mp-uboot.dtb
  sudo rm /tmp/${UNIT}-uboot.dtb
elif [ "$UNIT" == "rgb10" ]; then
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB_ALT} ${mountpoint}/rk3326-odroidgo2-linux-v11.dtb.oga11
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${KERNEL_DTB_RGB10S} ${mountpoint}/rk3326-odroidgo2-linux-v11.dtb.rgb10s
fi

# G350, Mini M: "Loading..." on the console while the initramfs mounts the root (scripts/bootlogo).
if [ "$UNIT" == "g350" ] || [ "$UNIT" == "xumini" ]; then
  sudo install -D -m 0755 scripts/bootlogo/initramfs-loading Arkbuild/etc/initramfs-tools/scripts/init-top/darkmoss-loading
fi
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
