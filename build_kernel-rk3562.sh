#!/bin/bash

# RK3562 (AISLPC RG52 Mini): kernel, firmware and loader from bmdhacks'
# dArkOS_rg52mini port, pinned. His BSP/ holds what the stock EmuELEC image
# provides and the kernel cannot build: librga, WiFi/BT firmware, the loader
# area and the U-Boot FIT with its charge images.

RK3562_PORT_REPO=https://github.com/bmdhacks/dArkOS_rg52mini.git
RK3562_PORT_SHA=10f5c7b68288e33ca2cbc4f83a69cce5eb7885d9
RK3562_KERNEL_REPO=https://github.com/bmdhacks/kernel_rk3562.git
RK3562_KERNEL_SHA=557e5c28ab406a2c8be3d553328c7d784412da0c

fetch_pinned() {
  # $1 repo, $2 sha, $3 dir, $4.. sparse paths (none = whole tree)
  local repo=$1 sha=$2 dir=$3
  shift 3
  if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$sha" ]; then
    return 0
  fi
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$repo"
  if [ $# -gt 0 ]; then
    git -C "$dir" sparse-checkout set --no-cone "$@"
  fi
  git -C "$dir" fetch -q --depth=1 origin "$sha" && git -C "$dir" checkout -q FETCH_HEAD
}

echo "Fetching the RK3562 BSP and kernel..."
fetch_pinned $RK3562_PORT_REPO $RK3562_PORT_SHA rk3562_port /BSP/
verify_action
export BSP_PATH="${PWD}/rk3562_port/BSP"
fetch_pinned $RK3562_KERNEL_REPO $RK3562_KERNEL_SHA kernel_rk3562
verify_action
KERNEL_SRC="${PWD}/kernel_rk3562"
DTB_FILE="${KERNEL_SRC}/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb"

if ! command -v pngtopnm &> /dev/null; then
  sudo apt -y update
  sudo apt -y install netpbm
fi
pngtopnm logos/unrotated/dArkMoss${UNIT}.png | ppmquant 224 | pnmnoraw > "$KERNEL_SRC/drivers/video/logo/logo_linux_clut224.ppm"
verify_action
make -C "$KERNEL_SRC" ${UNIT}_defconfig
verify_action
"$KERNEL_SRC/scripts/config" --file "$KERNEL_SRC/.config" -e LOGO -e LOGO_LINUX_CLUT224
make -C "$KERNEL_SRC" olddefconfig
verify_action
make -C "$KERNEL_SRC" -j$(nproc) Image rockchip/${UNIT_DTB}.dtb modules
verify_action
KERNEL_VERSION=$(make -C "$KERNEL_SRC" -s kernelrelease)

mountpoint=mnt/boot
mkdir -p ${mountpoint}
sudo mount ${LOOP_DEV}p3 ${mountpoint}
sudo cp "$KERNEL_SRC/arch/arm64/boot/Image" ${mountpoint}/
sudo cp "$DTB_FILE" ${mountpoint}/${UNIT_DTB}.dtb
# U-Boot's charge animation reads these from the boot partition.
sudo cp ${BSP_PATH}/battery_*.bmp ${mountpoint}/

sudo make -C "$KERNEL_SRC" INSTALL_MOD_PATH="${PWD}/Arkbuild" modules_install
verify_action
sudo rm -f Arkbuild/lib/modules/${KERNEL_VERSION}/build Arkbuild/lib/modules/${KERNEL_VERSION}/source

sudo mkdir -p Arkbuild/lib/firmware/
# -L: the BSP tree links its blobs; a few links dangle, hence no error check.
sudo rsync -aL --ignore-errors ${BSP_PATH}/firmware/ Arkbuild/lib/firmware/ || \
  sudo cp -rL ${BSP_PATH}/firmware/. Arkbuild/lib/firmware/ || true
if [ ! -d Arkbuild/lib/firmware/aic8800 ]; then
  echo "ERROR: the BSP WiFi firmware did not install."
  exit 1
fi

sudo cp "$KERNEL_SRC/.config" Arkbuild/boot/config-${KERNEL_VERSION}
sudo touch Arkbuild/lib/modules/${KERNEL_VERSION}/modules.builtin.modinfo
call_chroot "uname() { echo ${KERNEL_VERSION}; }; export -f uname; depmod ${KERNEL_VERSION}; update-initramfs -c -k ${KERNEL_VERSION}"
verify_action
if ! command -v mkimage &> /dev/null; then
  sudo apt -y update
  sudo apt -y install u-boot-tools
fi

# Root is the SD card (mmcblk1; the eMMC with the stock OS is mmcblk0).
rm -rf initrd
mkdir initrd
sudo cp Arkbuild/boot/initrd.img-${KERNEL_VERSION} initrd/initrd.img
sudo chown $(id -u):$(id -g) initrd/initrd.img
cd initrd
zstd -d -c initrd.img | cpio -idm
rm -f initrd.img
sed -i '/local dev_id\=/c\\tlocal dev_id\=\"/dev/mmcblk1p4\"' scripts/local
mkdir -p lib/firmware
wget -t 3 -T 60 https://github.com/CaffeeLake/wireless-regdb/raw/refs/heads/master/regulatory.db -O lib/firmware/regulatory.db
# The fsck hook finds no root device in the chroot and leaves out fsck and
# logsave, which the initramfs then calls anyway: exit 127, panic.
for bin in /sbin/fsck /sbin/logsave /sbin/fsck.btrfs; do
  src="../Arkbuild${bin}"
  if [ -f "$src" ]; then
    cp "$src" ".${bin}"
    for lib in $(ldd "$src" 2>/dev/null | grep -o '/lib[^ ]*'); do
      mkdir -p ".$(dirname "$lib")"
      cp -n "$lib" ".$lib" 2>/dev/null || true
    done
  fi
done
find . | cpio -H newc -o | gzip -c > ../uInitrd
cd ..
sudo mv uInitrd ${mountpoint}/uInitrd
rm -rf initrd

# idbloader (sectors 64-16383) and the U-Boot FIT (uboot partition, 16384).
sudo dd if=${BSP_PATH}/bootloader_area.img of=$LOOP_DEV bs=$SECTOR_SIZE skip=64 seek=64 count=16320 conv=notrunc
verify_action
sudo dd if=${BSP_PATH}/uboot-${UNIT}.img of=$LOOP_DEV bs=$SECTOR_SIZE seek=16384 conv=notrunc
verify_action
