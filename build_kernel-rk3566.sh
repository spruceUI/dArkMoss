#!/bin/bash

source ./scripts/ci/build-cache.sh

# Build and install custom kernel from christianhaitian/linux
KERNEL_SRC=main
KERNEL_REPO=https://github.com/christianhaitian/kernel_5_10_226.git

# Kernel artifacts are cached on a release, keyed by everything that can change
# what comes out: the upstream kernel SHA, the defconfig name, the unit, and the
# boot logos (which are compiled into the kernel, so they are real inputs). A
# hit skips a ~12 minute compile; a miss builds and publishes as before.
# The trailing token is the cache FORMAT version, not a content input. The key
# otherwise describes only what goes into the kernel, not what we choose to pack
# out of it - so when the file list here changes, an old tarball would still key
# as a hit and restore an incomplete tree. That is exactly how a pack missing
# .config would have survived its own fix. Bump it whenever the tar list below
# changes.
KERNEL_CACHE_KEY="$(bc_key "$(bc_remote_sha "$KERNEL_REPO")" \
    "rk3566_optimized_linux_defconfig" "$UNIT" "$UNIT_DTB" \
    "logos/unrotated/dArkMoss${UNIT}.png" "logos/unrotated/dArkMosshdmi.png" \
    "fmt2")"
KERNEL_CACHE_ASSET="kernel-${UNIT}-${KERNEL_CACHE_KEY}.tar.zst"
KERNEL_FROM_CACHE=n

# The tarball holds the INSTALLED results, not the object tree: the Image and
# dtbs, and the module and firmware trees already staged into Arkbuild. Packing
# the source tree instead would not work - modules_install copies .ko files out
# of the object tree, and keeping several GB of objects to avoid a 12 minute
# compile is a bad trade.
if bc_fetch "$KERNEL_CACHE_ASSET" "kernel-cache.tar.zst"; then
  if sudo tar --zstd -xf kernel-cache.tar.zst; then
    KERNEL_FROM_CACHE=y
    # The tarball has to be unpacked as root - Arkbuild's module tree is
    # root-owned and must stay that way - but $KERNEL_SRC is a workspace
    # directory the build writes into as the normal user later (it clones
    # rg503Kernel and rk356x-uboot inside it). Leaving it root-owned makes those
    # clones fail with "could not create work tree dir: Permission denied", and
    # a failed clone here poisons everything downstream. Hand it back.
    sudo chown -R "$(id -u):$(id -g)" "$KERNEL_SRC" 2>/dev/null
    echo "Kernel restored from build cache; skipping the compile and modules_install."
  else
    echo "Kernel cache tarball would not extract - building from source."
  fi
  rm -f kernel-cache.tar.zst
fi

if [ "$KERNEL_FROM_CACHE" != "y" ] && [ ! -d "$KERNEL_SRC" ]; then
  git clone --recursive --depth=1 $KERNEL_REPO $KERNEL_SRC
fi
cd $KERNEL_SRC
# Change the boot logo depending on the device. Skipped on a cache hit: the
# logos are an input to the cache key, so a cached Image already has them, and
# there is no drivers/video/logo in a restored tree to write into.
if [ "$KERNEL_FROM_CACHE" != "y" ] && [[ -e "../logos/unrotated/dArkMoss${UNIT}.png" ]]; then
  apt list --installed 2>/dev/null | grep -q "netpbm"
  if [[ $? != "0" ]]; then
    sudo apt -y update
    sudo apt -y install netpbm
  fi	
  pngtopnm ../logos/unrotated/dArkMoss${UNIT}.png | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_linux_clut224.ppm
  pngtopnm ../logos/unrotated/dArkMosshdmi.png | ppmquant 224 | pnmnoraw > drivers/video/logo/logo_hdmi_clut224.ppm
fi

if [ "$KERNEL_FROM_CACHE" != "y" ]; then
  make ARCH=arm64 rk3566_optimized_linux_defconfig
  CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 KERNEL_DTS=rk3566 KERNEL_CONFIG=rk3566_optimized_linux_defconfig
  verify_action
fi
cd ..

# Install kernel modules, then pack the installed results for the next build.
# On a cache hit both trees are already in place from the tarball.
if [ "$KERNEL_FROM_CACHE" != "y" ]; then
  sudo make -C $KERNEL_SRC ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=../Arkbuild modules_install
  sudo cp -Rv $KERNEL_SRC/lib/firmware/ Arkbuild/usr/lib/

  echo "Packing the kernel for the build cache..."
  if sudo tar --zstd -cf kernel-cache.tar.zst \
      "$KERNEL_SRC/arch/arm64/boot/Image" \
      "$KERNEL_SRC/arch/arm64/boot/dts/rockchip" \
      "$KERNEL_SRC/lib/firmware" \
      "$KERNEL_SRC/.config" \
      Arkbuild/lib/modules \
      Arkbuild/usr/lib/firmware; then
    bc_publish "$KERNEL_CACHE_ASSET" kernel-cache.tar.zst
  else
    echo "Kernel pack failed - not publishing, build continues."
  fi
  rm -f kernel-cache.tar.zst
fi

mountpoint=mnt/boot
mkdir -p ${mountpoint}
sudo mount ${LOOP_DEV}p3 ${mountpoint}

# Copy kernel, device tree, and modules into target rootfs
KERNEL_VERSION=$(basename $(ls Arkbuild/lib/modules))
sudo cp $KERNEL_SRC/.config Arkbuild/boot/config-${KERNEL_VERSION}
sudo cp $KERNEL_SRC/arch/arm64/boot/Image ${mountpoint}/
if [ "$UNIT" == "503" ]; then
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb ${mountpoint}/${UNIT_DTB}.dtb
  cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb
else
  sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb ${mountpoint}/
  if [[ "$UNIT" == *"353"* ]]; then
    sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}-notimingchange.dtb ${mountpoint}/
  elif [ "$UNIT" == "rgb30" ]; then
    sudo mkdir -p Arkbuild/usr/local/bin/rgb30dtbs/
    sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb Arkbuild/usr/local/bin/rgb30dtbs/${UNIT_DTB}.dtb.v1
    sudo cp $KERNEL_SRC/arch/arm64/boot/dts/rockchip/${UNIT_DTB}-v2.dtb Arkbuild/usr/local/bin/rgb30dtbs/${UNIT_DTB}.dtb.v2
  fi
fi

# Copy firmware blobs (follow symlinks, ignore dangling ones)
echo "Installing firmware..."
sudo mkdir -p Arkbuild/lib/firmware/
# Use rsync to handle symlinks gracefully
sudo rsync -aL --ignore-errors $KERNEL_SRC/lib/firmware/ Arkbuild/lib/firmware/ 2>/dev/null || \
 sudo cp -rL $KERNEL_SRC/lib/firmware/* Arkbuild/lib/firmware/ 2>/dev/null || true
 
# Create uInitrd from generated initramfs
#sudo cp /usr/bin/qemu-aarch64-static Arkbuild/usr/bin/
KERNEL_VERSION=$(basename $(find Arkbuild/lib/modules -maxdepth 1 -mindepth 1 -type d))
# Create symlink so depmod/initramfs can find modules for uname -r (host kernel)
sudo touch Arkbuild/lib/modules/${KERNEL_VERSION}/modules.builtin.modinfo
call_chroot "uname() { echo ${KERNEL_VERSION}; }; export -f uname; depmod ${KERNEL_VERSION}; update-initramfs -c -k ${KERNEL_VERSION}"
#sudo rm Arkbuild/usr/bin/qemu-aarch64-static
sudo cp Arkbuild/boot/initrd.img-* ${mountpoint}/initrd.img
if ! command -v mkimage &> /dev/null; then
  sudo apt -y update
  sudo apt -y install u-boot-tools
fi
mkdir initrd

#Update uInitrd to force booting from mmcblk1p4
sudo mv ${mountpoint}/initrd.img initrd/.
cd initrd
zstd -d -c initrd.img | cpio -idmv
rm -f initrd.img
sed -i '/local dev_id\=/c\\tlocal dev_id\=\"/dev/mmcblk1p4\"' scripts/local
#Add regulatory.db and regulatory.db.p7s
mkdir -p lib/firmware
wget https://github.com/CaffeeLake/wireless-regdb/raw/refs/heads/master/regulatory.db -O lib/firmware/regulatory.db -O lib/firmware/regulatory.db
#wget -t 5 -T 60 https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain/regulatory.db.p7s -O lib/firmware/regulatory.db.p7s
# Fix: fsck hook fails to detect root fstype during chroot build because
# /dev/mmcblk1p4 doesn't exist, so it skips copying fsck/logsave entirely.
# The initramfs scripts/functions still calls logsave unconditionally, and
# the missing binary causes exit code 127 -> panic at boot.
for bin in /sbin/fsck /sbin/logsave /sbin/e2fsck /sbin/fsck.ext4; do
  src="../Arkbuild${bin}"
  if [ -f "$src" ]; then
    cp "$src" ".${bin}"
    # Copy required shared libraries
    for lib in $(ldd "$src" 2>/dev/null | grep -o '/lib[^ ]*'); do
      mkdir -p ".$(dirname "$lib")"
      cp -n "$lib" ".$lib" 2>/dev/null || true
    done
  fi
done
# We also need to copy the 5.10 kernel compatible BT firmware files or BT will not initialize correctly
mkdir -p lib/firmware/rtl_bt/
if [[ "$UNIT" != "rgb20pro" ]] && [[ "$UNIT" != *"miniloong"* ]]; then
  sudo cp ../Arkbuild/usr/lib/firmware/rtl_bt/rtl8821cs_* lib/firmware/rtl_bt/
else
  sudo cp ../firmware/rtl8723ds/rtl8723ds_config.bin lib/firmware/rtl_bt/rtl8723d_config.bin
  sudo cp ../firmware/rtl8723ds/rtl8723ds_fw.bin lib/firmware/rtl_bt/rtl8723d_fw.bin
fi
find . | cpio -H newc -o | gzip -c > ../uInitrd
sudo mv ../uInitrd ../${mountpoint}/uInitrd
cd ..
rm -rf initrd
sudo rm -f ${mountpoint}/initrd.img

# Build uboot and resource and install it to the image
cd $KERNEL_SRC
if [[ "$UNIT" == "503" ]] || [[ "$UNIT" == *"353"* ]] || [[ "$UNIT" == *"miniloong"* ]]; then
  #cp arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb .
  # Next line generates the resource.img file needed to flash to the image and to build the uboot
  git clone --depth=1 https://github.com/rockchip-linux/rkbin
  cd rkbin/tools
  #cp ../../arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb .
  if [[ "$UNIT" == "503" ]]; then
    cp ../../../misc/rk3566/device_off_charging_bmps/rg503/* .
    #cp ../../arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb .
    #cp ../../arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb rk-kernel.dtb
  elif [[ "$UNIT" == *"miniloong"* ]]; then
    cp ../../../misc/rk3566/device_off_charging_bmps/miniloong/*.bmp .
    #cp ../../arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb .
    cp ../../arch/arm64/boot/dts/rockchip/${UNIT_DTB}.dtb rk-kernel.dtb
  else
    cp ../../../misc/rk3566/device_off_charging_bmps/rg353/* .
  fi
  # Use Anbernic's resource.img files to provide onscreen battery charging state while off
  ./resource_tool --pack *.bmp rk-kernel.dtb
  cp resource.img ../../.
  cd ../..
  rm -rf rkbin
  #scripts/mkimg --dtb ${UNIT_DTB}.dtb
else
  # For some reason, supported PowKiddy rk3566 devices need resource.img
  # generated from the RG503 Kernel source.
  #
  # That means a SECOND full kernel compile - about ten minutes - to produce one
  # small image holding the off-charging battery screen. The output depends only
  # on the rg503Kernel tree, so cache it on the release and the second compile
  # happens once ever rather than once a build.
  RESOURCE_CACHE_KEY="$(bc_key "$(bc_remote_sha https://github.com/christianhaitian/rg503Kernel.git)" "rk3566_optimized_linux_defconfig")"
  RESOURCE_CACHE_ASSET="resource-rk3566-${RESOURCE_CACHE_KEY}.img"

  if ! bc_fetch "$RESOURCE_CACHE_ASSET" "resource.img"; then
    # Built in a subshell so a failure in here cannot move the caller's working
    # directory. The original "cd rg503Kernel ... cd .." pairing looks safe
    # until the clone fails: the cd in fails, the cd out still runs, and the
    # whole rest of the script executes one directory too high - which is
    # exactly how a permissions error on the clone ended up producing an image
    # with no resource.img flashed into it.
    (
      set -e
      git clone --recursive --depth=1 https://github.com/christianhaitian/rg503Kernel.git
      cd rg503Kernel
      make ARCH=arm64 rk3566_optimized_linux_defconfig
      CFLAGS=-Wno-deprecated-declarations make -j$(nproc) ARCH=arm64 KERNEL_DTS=rk3566 KERNEL_CONFIG=rk3566_optimized_linux_defconfig
      cp arch/arm64/boot/dts/rockchip/rk3566.dtb .
      scripts/mkimg --dtb rk3566.dtb
      cp resource.img ../.
    )
    if [ -s resource.img ]; then
      bc_publish "$RESOURCE_CACHE_ASSET" resource.img
    else
      echo "ERROR: resource.img was not produced - the image will not boot."
    fi
    # The tree is only ever needed for that one file.
    rm -rf rg503Kernel
  fi
fi
git clone --depth=1 https://github.com/christianhaitian/rk356x-uboot.git
git clone https://github.com/christianhaitian/rkbin.git
mkdir -p ./prebuilts/gcc/linux-x86/aarch64/
OPT_TOOLCHAIN_DIR="/opt/toolchains/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"
LOCAL_TOOLCHAIN_DIR="./prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"
if [[ -d "$OPT_TOOLCHAIN_DIR" && ! -d "$LOCAL_TOOLCHAIN_DIR" ]]; then
    ln -s "$OPT_TOOLCHAIN_DIR" "$LOCAL_TOOLCHAIN_DIR"
fi
cd rk356x-uboot
cp ../resource.img rk3566_tool/Image/
./make.sh rk3566
./make.sh trust
# Since I don't know how to build a proper loader1.img file
# We'll cheat and use the one from Anbernic's stock OS
# More information on how it was obtained is available from
# here: https://github.com/christianhaitian/rkbin/commit/1302e7af2b34f18496997f52e3cf5a358829db73
cp ../rkbin/bin/rk35/Anbernic_Stock_loader1.img .
#sudo cp uboot.img ../../Arkbuild/usr/local/bin/uboot.img.jelos

echo "Flashing loader1.img, trust.img, uboot.img and resource.img..."
sudo dd if=Anbernic_Stock_loader1.img of=$LOOP_DEV bs=$SECTOR_SIZE seek=64 conv=notrunc
sudo dd if=trust.img of=$LOOP_DEV bs=$SECTOR_SIZE seek=8192 conv=notrunc
sudo dd if=uboot.img of=$LOOP_DEV bs=$SECTOR_SIZE seek=16384 conv=notrunc
sudo dd if=rk3566_tool/Image/resource.img of=$LOOP_DEV bs=$SECTOR_SIZE seek=24576 conv=notrunc

# Last but not least, create undervolt dtbo files and place them in an overlays subfolder in the fat partition
sudo mkdir -p ../../${mountpoint}/overlays
for DTS in light medium maximum
do
  wget -t 3 -T 60 --no-check-certificate https://raw.githubusercontent.com/christianhaitian/rk3566_core_builds/refs/heads/master/shell-scripts/undervolt/undervolt.${DTS}.dts
  dtc -@ -I dts -O dtb -o undervolt.${DTS}.dtbo undervolt.${DTS}.dts
  sudo mv undervolt.${DTS}.dtbo ../../${mountpoint}/overlays/
done

cd ../..
