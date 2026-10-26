#!/bin/bash

echo -e "Setup the Image file...\n\n"

# Image creation
iName=`echo ${UNIT} | tr '[:lower:]' '[:upper:]'`
DISK="dArkMoss_${iName}_${DEBIAN_CODE_NAME}_${BUILD_DATE}.img"
dd if=/dev/zero of="${DISK}" bs=1M count=0 seek="${DISK_SIZE}" conv=fsync
parted -s "${DISK}" mklabel msdos
parted -s "${DISK}" -a min unit s mkpart primary fat32 ${SYSTEM_PART_START} ${SYSTEM_PART_END}
parted -s "${DISK}" set 1 boot on
parted -s "${DISK}" -a min unit s mkpart primary ${ROOT_FILESYSTEM_FORMAT} ${STORAGE_PART_START} ${STORAGE_PART_END}
#parted -s "${DISK}" set 2 lba off
sync



# Build uboot and install it to the image
if [ "$UNIT" == "pixel2" ]; then
  # RK3326S: Twig-Next's U-Boot (AveyondFly's Rockchip next-dev); RG351MP-u-boot never reached
  # Linux on the PX30S (B197). It loads its own DTB from BOOT (build_kernel.sh) and extlinux.conf.
  git init -q u-boot-${CHIPSET}
  git -C u-boot-${CHIPSET} fetch -q --depth=1 https://github.com/AveyondFly/u-boot.git e769657b0aff93eabd97fdc8f80f5808f3d58312
  verify_action
  git -C u-boot-${CHIPSET} checkout -q FETCH_HEAD
elif [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ]; then
  git clone --depth=1 https://github.com/christianhaitian/RG351MP-u-boot u-boot-${CHIPSET}
else
  git clone --depth=1 https://github.com/christianhaitian/u-boot-${CHIPSET}
fi
cd u-boot-${CHIPSET}
if [ "$UNIT" == "xumini" ]; then
  # xumini-uboot.dts is ours; RG351MP-u-boot has no such unit upstream.
  patch -p1 < ../patches/xumini/uboot/0001-arch-arm-dts-Makefile.patch
  cp ../patches/xumini/uboot/xumini-uboot.dts arch/arm/dts/
fi
if [ "$UNIT" == "pixel2" ]; then
  # Twig-Next's defconfig: PX30S DDR training (dmc_fsp), DTB from BOOT, distro boot.
  cp ../patches/pixel2/uboot/rk3326s_defconfig configs/
  # Twig-Next's rkbin: the PX30S DDR blob, miniloader, BL31 (at 0x40000), BL32 and packing tools.
  RKBIN_URL="https://github.com/rockchip-linux/rkbin/raw/74213af1e952c4683d2e35952507133b61394862"
  mkdir -p rkbin
  while read -r sum file; do
    wget -q -O rkbin/${file##*/} ${RKBIN_URL}/${file}
    echo "${sum}  rkbin/${file##*/}" | sha256sum -c -
    verify_action
  done <<'BLOBS'
2df577824953bea3584282e7f5118c96620e1348dbc378d50604fe07c70eb3e4 bin/rk33/rk3326_ddr_333MHz_v2.11.bin
473aacd5378f356757a71efeb54f4339925db154fbce288df7e3c1177f45bc28 bin/rk33/rk3326_miniloader_v1.40.bin
387aaee716a6753a9e6dd18c72b27783d125a294f6aa817531a5a6f340f16080 bin/rk33/rk3326_bl31_v1.34.elf
2067217f7de6ce438f75cd36c0fcc606a93282837bdcaeb6e2f172ab5e52e996 bin/rk33/rk3326_bl32_v2.19.bin
e26a311d449c6254d0d89ecaf8cd1870438205e07a66b27265d68830b8977439 tools/loaderimage
059b622fc7597da572d8fcf726da3897e498985b3e922015f1413fb45f89963a tools/trust_merger
BLOBS
  chmod +x rkbin/loaderimage rkbin/trust_merger
fi
if [ "$UNIT" == "g350" ]; then
  # g350-uboot.dts pins vccio_sd (the TF1 IO rail) at 1.8 V, so U-Boot forces it
  # down mid-boot and loses the card; a 1.8-3.3 V range leaves it as booted.
  patch -p1 < ../patches/g350/uboot/0001-g350-uboot-vccio_sd-range.patch
  verify_action
  # G350s ship with one of two panels: IDs for both, read by the panel-id fix below.
  patch -p1 < ../patches/g350/uboot/0002-g350-uboot-two-panels.patch
  verify_action
fi
# Opt-in fixes from patches/rk3326/uboot: a unit lists only what it was tested with.
# uboot-dtb: U-Boot loads uboot.dtb, whatever hwrev reads; build_kernel.sh ships it.
# panel-id: read the panel's ID and switch to the sibling panel node it names.
case "$UNIT" in
  g350)   UBOOT_OPTIN="uboot-dtb panel-id" ;;
  xumini) UBOOT_OPTIN="uboot-dtb" ;;
  *)      UBOOT_OPTIN="" ;;
esac
for fix in $UBOOT_OPTIN; do
  patch -p1 < "../patches/rk3326/uboot/${fix}.patch"
  verify_action
done
if [ "$UNIT" == "pixel2" ]; then
  # Built with Rockchip's own default toolchain (utils.sh's Linaro 6.3.1) and packed as
  # Twig-Next's rkhelper does for RK3326S, into the sd_fuse/ that make.sh would fill.
  make ARCH=arm rk3326s_defconfig
  make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)
  verify_action
  mkdir -p sd_fuse
  ./tools/mkimage -n px30 -T rksd -d rkbin/rk3326_ddr_333MHz_v2.11.bin -C bzip2 sd_fuse/idbloader.img
  verify_action
  cat rkbin/rk3326_miniloader_v1.40.bin >> sd_fuse/idbloader.img
  verify_action
  rkbin/loaderimage --pack --uboot u-boot-dtb.bin sd_fuse/uboot.img 0x00200000
  verify_action
  cat > trust.ini <<'EOF'
[VERSION]
MAJOR=1
MINOR=0
[BL30_OPTION]
SEC=0
[BL31_OPTION]
SEC=1
PATH=rkbin/rk3326_bl31_v1.34.elf
ADDR=0x00040000
[BL32_OPTION]
SEC=1
PATH=rkbin/rk3326_bl32_v2.19.bin
ADDR=0x08400000
[BL33_OPTION]
SEC=0
[OUTPUT]
PATH=sd_fuse/trust.img
EOF
  rkbin/trust_merger trust.ini
  verify_action
else
  ./make.sh odroidgoa
fi
# The loader build can stop short (a pack size limit) without this script noticing; no loader means no boot.
if ! { test -s sd_fuse/idbloader.img && test -s sd_fuse/uboot.img && test -s sd_fuse/trust.img; }; then
  echo "ERROR: the U-Boot build left no sd_fuse/idbloader.img, uboot.img and trust.img"
  false
fi
verify_action

dd if="sd_fuse/idbloader.img" of="../${DISK}" bs=512 seek=64 conv=sync,noerror,notrunc
dd if="sd_fuse/uboot.img" of="../${DISK}" bs=512 seek=16384 conv=sync,noerror,notrunc
dd if="sd_fuse/trust.img" of="../${DISK}" bs=512 seek=24576 conv=sync,noerror,notrunc
if [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ]; then
  cp arch/arm/dts/${UNIT}-uboot.dtb /tmp/
fi
cd ..
rm -rf u-boot-${CHIPSET}
