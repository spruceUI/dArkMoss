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
if [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ] || [ "$UNIT" == "pixel2" ]; then
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
  patch -p1 < ../patches/pixel2/uboot/0001-arch-arm-dts-Makefile.patch
  # PX30S DDR set point init, run by boot.ini for the /darkmoss-px30s boot.
  patch -p1 < ../patches/pixel2/uboot/0002-px30-dmc_fsp-command.patch
  cp ../patches/pixel2/uboot/pixel2-uboot.dts arch/arm/dts/
  # RK3326S needs newer rkbin blobs (twigUI-next's); this BL31 loads at 0x40000.
  RKBIN_URL="https://github.com/rockchip-linux/rkbin/raw/74213af1e952c4683d2e35952507133b61394862/bin/rk33"
  while read -r sum blob; do
    wget -q -O tools/rk_tools/bin/rk33/${blob} ${RKBIN_URL}/${blob}
    echo "${sum}  tools/rk_tools/bin/rk33/${blob}" | sha256sum -c -
    verify_action
  done <<'BLOBS'
2df577824953bea3584282e7f5118c96620e1348dbc378d50604fe07c70eb3e4 rk3326_ddr_333MHz_v2.11.bin
473aacd5378f356757a71efeb54f4339925db154fbce288df7e3c1177f45bc28 rk3326_miniloader_v1.40.bin
387aaee716a6753a9e6dd18c72b27783d125a294f6aa817531a5a6f340f16080 rk3326_bl31_v1.34.elf
2067217f7de6ce438f75cd36c0fcc606a93282837bdcaeb6e2f172ab5e52e996 rk3326_bl32_v2.19.bin
BLOBS
  sed -i 's/rk3326_ddr_333MHz_v1.10.bin/rk3326_ddr_333MHz_v2.11.bin/g; s/rk3326_miniloader_v1.12.bin/rk3326_miniloader_v1.40.bin/g' \
    make.sh tools/rk_tools/RKBOOT/RK3326MINIALL.ini
  sed -i 's/rk3326_bl31_v1.14.elf/rk3326_bl31_v1.34.elf/; s/^ADDR=0x00010000$/ADDR=0x00040000/; s/rk3326_bl32_v1.10.bin/rk3326_bl32_v2.19.bin/' \
    tools/rk_tools/RKTRUST/RK3326TRUST.ini
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
  pixel2) UBOOT_OPTIN="uboot-dtb" ;;
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
if [ "$UNIT" == "rg351mp" ] || [ "$UNIT" == "g350" ] || [ "$UNIT" == "a10mini" ] || [ "$UNIT" == "xumini" ] || [ "$UNIT" == "pixel2" ]; then
  cp arch/arm/dts/${UNIT}-uboot.dtb /tmp/
fi
cd ..
rm -rf u-boot-${CHIPSET}
