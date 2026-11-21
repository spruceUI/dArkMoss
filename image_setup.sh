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
# RG351P: RG351MP-u-boot carries rg351p-uboot.dts (the RG351 family U-Boot).
if [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ] || [ "$UNIT" == "rg351p" ]; then
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
if [ "$UNIT" == "g350" ]; then
  # g350-uboot.dts pins vccio_sd (the TF1 IO rail) at 1.8 V, so U-Boot forces it
  # down mid-boot and loses the card; a 1.8-3.3 V range leaves it as booted.
  patch -p1 < ../patches/g350/uboot/0001-g350-uboot-vccio_sd-range.patch
  verify_action
  # G350s ship with one of two panels: IDs for both, read by the panel-id fix below.
  patch -p1 < ../patches/g350/uboot/0002-g350-uboot-two-panels.patch
  verify_action
fi
if [ "$UNIT" == "a10mini" ]; then
  # One image for the A10 Mini and the V4: both panels, told apart by the panel-id fix below.
  patch -p1 < ../patches/a10mini/uboot/0001-a10mini-uboot-two-panels.patch
  verify_action
  # rkbin's DDR init v2.12 (as stock ArkOS4Clone): v1.10 corrupts RAM on some V4s.
  cp ../patches/a10mini/uboot/rk3326_ddr_333MHz_v2.12.bin tools/rk_tools/bin/rk33/
  sed -i 's/rk3326_ddr_333MHz_v1\.10\.bin/rk3326_ddr_333MHz_v2.12.bin/' make.sh
  grep -q 'rk3326_ddr_333MHz_v2.12.bin' make.sh
  verify_action
fi
# Opt-in fixes from patches/rk3326/uboot: a unit lists only what it was tested with.
# uboot-dtb: U-Boot loads uboot.dtb, whatever hwrev reads; build_kernel.sh ships it.
# panel-id: read the panel's ID and switch to the sibling panel node it names.
# low-battery: boot down to 3.1 V instead of 3.53 V.
# low-battery-3v4: boot down to 3.4 V, for a unit whose kernel dts powers off below 3.4 V.
case "$UNIT" in
  g350)   UBOOT_OPTIN="uboot-dtb panel-id low-battery" ;;
  a10mini) UBOOT_OPTIN="panel-id low-battery" ;;
  xumini) UBOOT_OPTIN="uboot-dtb low-battery" ;;
  v10)    UBOOT_OPTIN="low-battery" ;;
  # The RG351P's dts powers off below 3.4 V (power_off_thresd), so U-Boot stops there too.
  rg351p) UBOOT_OPTIN="uboot-dtb low-battery-3v4" ;;
  *)      UBOOT_OPTIN="" ;;
esac
for fix in $UBOOT_OPTIN; do
  patch -p1 < "../patches/rk3326/uboot/${fix}.patch"
  verify_action
done
./make.sh odroidgoa

dd if="sd_fuse/idbloader.img" of="../${DISK}" bs=512 seek=64 conv=sync,noerror,notrunc
dd if="sd_fuse/uboot.img" of="../${DISK}" bs=512 seek=16384 conv=sync,noerror,notrunc
dd if="sd_fuse/trust.img" of="../${DISK}" bs=512 seek=24576 conv=sync,noerror,notrunc
if [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ] || [ "$UNIT" == "rg351p" ]; then
  cp arch/arm/dts/${UNIT}-uboot.dtb /tmp/
fi
cd ..
rm -rf u-boot-${CHIPSET}
