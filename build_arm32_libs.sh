#!/bin/bash

# Christian's armhf libraries (SDL2, librga, libgo2) without the RetroArch build
# that normally brings in his 32-bit chroot.

source ./scripts/ci/build-cache.sh

ARM32_LIB_DIR=Arkbuild/usr/lib/arm-linux-gnueabihf
ARM32_CACHE_KEY="$(bc_key utils.sh build_deps.sh build_sdl2.sh build_arm32_libs.sh \
    needed_packages.txt needed_dev_packages.txt "${DEBIAN_CODE_NAME}" "${CHIPSET}" \
    "$(bc_remote_sha "https://github.com/christianhaitian/${CHIPSET}_core_builds.git")")"
ARM32_CACHE_ASSET="arm32-libs-${CHIPSET}-${ARM32_CACHE_KEY}.tar.zst"

if bc_fetch "$ARM32_CACHE_ASSET" arm32-libs.tar.zst && sudo tar --zstd -xpf arm32-libs.tar.zst; then
  echo "armhf libraries restored from build cache."
else
  ( setup_arkbuild32 )
  if sudo tar --zstd -cf arm32-libs.tar.zst ${ARM32_LIB_DIR}/libSDL2* ${ARM32_LIB_DIR}/librga.so* ${ARM32_LIB_DIR}/libgo2.so*; then
    bc_publish "$ARM32_CACHE_ASSET" arm32-libs.tar.zst
  fi
fi
rm -f arm32-libs.tar.zst
sudo chroot Arkbuild/ ldconfig -X
