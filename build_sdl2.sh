#!/bin/bash

if [ "$CHIPSET" == "rk3326" ]; then
  sub_folder=""
else
  sub_folder="build"
fi

if [ "$1" == "32" ]; then
  BITNESS="32"
  ARCH="arm-linux-gnueabihf"
  CHROOT_DIR="Arkbuild32"
else
  BITNESS="64"
  ARCH="aarch64-linux-gnu"
  CHROOT_DIR="Arkbuild"
fi

# xumini: our own RGA ROT_90 variant of the stock odroidgoa (ROT_270)
# kmsdrm patch, staged so it overwrites the upstream one before the build.
#
# e5plus: its 720x1280 panel is mounted the other way round from the
# Miniloong's, so it takes the Miniloong's RGA kmsdrm rotation patch (generic:
# it rotates any DSI output and leaves HDMI alone) with ROT_270 turned into
# ROT_90, matching fbcon=rotate:1. Same file name, so the patch order is the
# one the Miniloong build already proves. The Miniloong cursor patch is
# hard-coded to the 270 direction and is left out.
if [ "$UNIT" == "xumini" ]; then
  sudo mkdir -p ${CHROOT_DIR}/home/ark/xumini_sdl2_patch
  sudo cp patches/xumini/sdl2/sdl2-patch-0004-xumini-kmsdrm-rot90.patch \
    ${CHROOT_DIR}/home/ark/xumini_sdl2_patch/sdl2-patch-0004-odroidgoa-kmsdrm.patch
fi

# Build and install SDL2
if [ "$ARCH" == "arm-linux-gnueabihf" ]; then
  sudo chroot ${CHROOT_DIR}/ bash -c "source /root/.bashrc && cd /home/ark &&
    export CFLAGS=\"-Wno-error=int-conversion\" &&
    if [ ! -d ${CHIPSET}_core_builds ]; then git clone https://github.com/christianhaitian/${CHIPSET}_core_builds.git; fi &&
    cd ${CHIPSET}_core_builds &&
    if [[ ${UNIT} == *\"miniloong\"* ]]; then cp patches/${UNIT}/sdl2/*.patch patches/.; fi &&
    if [[ ${UNIT} == \"e5plus\" ]]; then sed 's/HAL_TRANSFORM_ROT_270/HAL_TRANSFORM_ROT_90/' patches/miniloong/sdl2/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch > patches/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch && grep -q HAL_TRANSFORM_ROT_90 patches/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch; fi &&
    if [[ ${UNIT} == \"xumini\" ]]; then cp -f /home/ark/xumini_sdl2_patch/*.patch patches/.; fi &&
    chmod 777 builds-alt.sh &&
    eatmydata ./builds-alt.sh sdl2 &&
    cd SDL/${sub_folder} &&
    make install
    "
else
  sudo chroot ${CHROOT_DIR}/ bash -c "source /root/.bashrc && cd /home/ark &&
    if [ ! -d ${CHIPSET}_core_builds ]; then git clone https://github.com/christianhaitian/${CHIPSET}_core_builds.git; fi &&
    cd ${CHIPSET}_core_builds &&
    if [[ ${UNIT} == *\"miniloong\"* ]]; then cp patches/${UNIT}/sdl2/*.patch patches/.; fi &&
    if [[ ${UNIT} == \"e5plus\" ]]; then sed 's/HAL_TRANSFORM_ROT_270/HAL_TRANSFORM_ROT_90/' patches/miniloong/sdl2/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch > patches/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch && grep -q HAL_TRANSFORM_ROT_90 patches/sdl2-patch-0004-miniloong-rotate-kmsdrm.patch; fi &&
    if [[ ${UNIT} == \"xumini\" ]]; then cp -f /home/ark/xumini_sdl2_patch/*.patch patches/.; fi &&
    chmod 777 builds-alt.sh &&
    eatmydata ./builds-alt.sh sdl2 &&
    cd SDL/build &&
    make install
    "
fi

extension=$(sudo grep -oP '(?<=extension=").*?(?=")' ${CHROOT_DIR}/home/ark/${CHIPSET}_core_builds/scripts/sdl2.sh)
if [ "$UNIT" == "v10" ]; then
  # V10: the stock odroidgoa RGA ROT_270 build (the "...rotated" one) for
  # its 320x480 portrait panel, not the a10miniv4 rotate180 pass that
  # "make install" leaves in place (see xumini below).
  sudo chroot ${CHROOT_DIR}/ bash -c "cp -f /home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension.rotated /usr/lib/${ARCH}/libSDL2-2.0.so.0.$extension"
elif [ "$UNIT" == "xumini" ]; then
  # The chroot's own "make install" left the LAST build in place (a10miniv4's
  # rotate180 pass, unconditional upstream); install our ROT_90 variant
  # instead, saved mid-build as "...rotated" before that pass ran.
  sudo chroot ${CHROOT_DIR}/ bash -c "cp -f /home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension.rotated /usr/lib/${ARCH}/libSDL2-2.0.so.0.$extension"
elif [ "$UNIT" == "a10mini" ]; then
  # Both builds for a10mini-panel.sh, which installs the V4's rotate-180 one on a V4.
  sudo chroot ${CHROOT_DIR}/ bash -c "cp -f /home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension /usr/lib/${ARCH}/."
  sudo mkdir -p Arkbuild/usr/local/share/a10mini
  sudo cp -f ${CHROOT_DIR}/home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension Arkbuild/usr/local/share/a10mini/sdl${BITNESS}-a10
  sudo cp -f ${CHROOT_DIR}/home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension.a10miniv4 Arkbuild/usr/local/share/a10mini/sdl${BITNESS}-v4
elif [[ "$UNIT" != *"rgb10"* ]] && [ "$UNIT" != "v10" ] && [ "$UNIT" != "rk2020" ] && [ "$CHIPSET" == "rk3326" ]; then
  sudo chroot ${CHROOT_DIR}/ bash -c "cp -f /home/ark/${CHIPSET}_core_builds/sdl2-${BITNESS}/libSDL2-2.0.so.0.$extension /usr/lib/${ARCH}/."
fi
sudo chroot ${CHROOT_DIR}/ bash -c "ln -sfv /usr/lib/${ARCH}/libSDL2.so /usr/lib/${ARCH}/libSDL2-2.0.so.0"
sudo chroot ${CHROOT_DIR}/ bash -c "ln -sfv /usr/lib/${ARCH}/libSDL2-2.0.so.0.${extension} /usr/lib/${ARCH}/libSDL2.so"
sudo chroot ${CHROOT_DIR}/ bash -c "ln -sfv /usr/include/SDL2 /usr/local/include/"
sudo chroot ${CHROOT_DIR}/ bash -c "rm -f /usr/bin/sdl2-config"
sudo chroot ${CHROOT_DIR}/ bash -c "ln -sfv /usr/lib/aarch64-linux-gnu/bin/sdl2-config /usr/bin/sdl2-config"
sudo cp -R ${CHROOT_DIR}/home/ark/${CHIPSET}_core_builds/SDL/include/* ${CHROOT_DIR}/usr/include/${ARCH}/SDL2/
sudo rm -rf ${CHROOT_DIR}/home/ark/${CHIPSET}_core_builds/SDL
