#!/bin/bash

source ./scripts/ci/build-cache.sh

echo -e "Installing build dependencies and needed packages...\n\n"

if [ "$1" == "32" ]; then
  BIT="32"
  ARCH="arm-linux-gnueabihf"
  CHROOT_DIR="Arkbuild32"
else
  BIT="64"
  ARCH="aarch64-linux-gnu"
  CHROOT_DIR="Arkbuild"
fi

# A prepared chroot is worth caching whole.
#
# Even batched, installing ~140 packages into an emulated arm64 chroot and then
# compiling librga and libgo2 in it is the most expensive phase of the build.
# The result is a pure function of the package lists and this script, so snapshot
# it and let later builds restore it instead.
#
# Kernel-owned paths are excluded: build_kernel runs before this and has its own
# cache entry, and overlapping the two would make each depend on the other's key.
# The live bind mounts (/dev, /proc, /sys, the ccache bind) are excluded too -
# tarring into those is the classic way to fill a disk with the host's own /dev.
DEPS_CACHE_KEY="$(bc_key needed_packages.txt needed_dev_packages.txt build_deps.sh \
    "${DEBIAN_CODE_NAME}" "${CHIPSET}" "${BUILD_ARMHF}" "${BIT}")"
DEPS_CACHE_ASSET="chroot-deps-${CHIPSET}-${BIT}-${DEPS_CACHE_KEY}.tar.zst"
DEPS_FROM_CACHE=n

if [ "$BIT" == "64" ] && bc_fetch "$DEPS_CACHE_ASSET" "chroot-deps.tar.zst"; then
  if sudo tar --zstd -xf chroot-deps.tar.zst; then
    DEPS_FROM_CACHE=y
    echo "Prepared chroot restored from build cache; skipping package install and in-chroot builds."
  else
    echo "Chroot cache tarball would not extract - preparing the chroot normally."
  fi
  rm -f chroot-deps.tar.zst
fi

if [ "$DEPS_FROM_CACHE" = "y" ]; then
  # The one thing the tarball cannot carry: the ccache bind mount, which is a
  # live mount rather than content.
  [ ! -d "${CHROOT_DIR}/home/ark/Arkbuild_ccache" ] && sudo mkdir -p ${CHROOT_DIR}/home/ark/Arkbuild_ccache
  sudo mount --bind ${PWD}/Arkbuild_ccache ${CHROOT_DIR}/home/ark/Arkbuild_ccache
  sudo chroot ${CHROOT_DIR}/ ldconfig -X
else

# Install additional needed packages and protect them from autoremove.
#
# One apt transaction for the whole list, not one per package. Upstream loops
# install_package over each name, which under qemu costs a full chroot+apt+dpkg
# database read every time - measured at ~96 minutes of a 145-minute RGB30
# build. install_packages_batch falls back to the per-package loop if the batch
# fails, so a package name that has gone away in the current Debian release is
# still found and skipped rather than killing the run.
NEEDED_PACKAGES=()
while read NEEDED_PACKAGE; do
  if [[ ! "$NEEDED_PACKAGE" =~ ^# ]] && [[ -n "$NEEDED_PACKAGE" ]]; then
    NEEDED_PACKAGES+=( "${NEEDED_PACKAGE}" )
  fi
done <needed_packages.txt
install_packages_batch $BIT "${NEEDED_PACKAGES[@]}"
protect_packages_batch $BIT "${NEEDED_PACKAGES[@]}"

# Install build dependencies
NEEDED_DEV_PACKAGES=()
while read NEEDED_DEV_PACKAGE; do
  if [[ ! "$NEEDED_DEV_PACKAGE" =~ ^# ]] && [[ -n "$NEEDED_DEV_PACKAGE" ]]; then
    NEEDED_DEV_PACKAGES+=( "${NEEDED_DEV_PACKAGE}" )
  fi
done <needed_dev_packages.txt
install_packages_batch $BIT "${NEEDED_DEV_PACKAGES[@]}"

# Default gcc and g++ to version 12 if gcc is newer than 12
GCC_VERSION=`sudo chroot ${CHROOT_DIR}/ bash -c "gcc --version | head -n 1 | awk '{print $3}' | cut -d' ' -f3 | cut -d'.' -f1"`
if (( GCC_VERSION > 12 )); then
  install_package $BIT gcc-12
  install_package $BIT g++-12
  sudo chroot ${CHROOT_DIR}/ bash -c "update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 10"
  sudo chroot ${CHROOT_DIR}/ bash -c "update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 20"
  sudo chroot ${CHROOT_DIR}/ bash -c "update-alternatives --set gcc /usr/bin/gcc-12"
  sudo chroot ${CHROOT_DIR}/ bash -c "update-alternatives --set g++ /usr/bin/g++-12"
fi

# Bind ccache to chroot to speed up consecutive builds
[ ! -d "${CHROOT_DIR}/home/ark/Arkbuild_ccache" ] && sudo mkdir -p ${CHROOT_DIR}/home/ark/Arkbuild_ccache
sudo mount --bind ${PWD}/Arkbuild_ccache ${CHROOT_DIR}/home/ark/Arkbuild_ccache
sudo chroot ${CHROOT_DIR}/ bash -c "[ -z \$(echo \$CCACHE_DIR | grep ccache) ]" && echo -e "export CCACHE_DIR=/home/ark/Arkbuild_ccache" | sudo tee -a ${CHROOT_DIR}/root/.bashrc > /dev/null
sudo chroot ${CHROOT_DIR}/ bash -c "[ -z \$(echo \$PATH | grep ccache) ]" && echo -e "export PATH=/usr/lib/ccache:\$PATH" | sudo tee -a ${CHROOT_DIR}/root/.bashrc > /dev/null
sudo chroot ${CHROOT_DIR}/ bash -c "/usr/sbin/update-ccache-symlinks"

# Symlink fix for DRM headers
sudo chroot ${CHROOT_DIR}/ bash -c "ln -s /usr/include/libdrm/ /usr/include/drm"

# Place libmali manually (assumes you have libmali.so or mali drivers ready)
ARCHITECTURE_ARRAY=("aarch64-linux-gnu")
if [[ "${BUILD_ARMHF}" == "y" ]]; then
  ARCHITECTURE_ARRAY+=("arm-linux-gnueabihf")
fi
for ARCHITECTURE in "${ARCHITECTURE_ARRAY[@]}"
do
  if [ "$ARCHITECTURE" == "aarch64-linux-gnu" ]; then
    FOLDER="aarch64"
  else
    FOLDER="armhf"
  fi
  sudo mkdir -p Arkbuild/usr/lib/${ARCHITECTURE}/
  wget --retry-connrefused --retry-on-http-error=429 --waitretry=20 -t 65 -T 60 --no-check-certificate -O ${whichmali} https://github.com/christianhaitian/${CHIPSET}_core_builds/raw/refs/heads/master/mali/${FOLDER}/${whichmali}
  sudo mv ${whichmali} Arkbuild/usr/lib/${ARCHITECTURE}/.
  cd Arkbuild/usr/lib/${ARCHITECTURE}
  sudo ln -sf ${whichmali} libMali.so
  for LIB in libEGL.so libEGL.so.1 libEGL.so.1.1.0 libGLES_CM.so libGLES_CM.so.1 libGLESv1_CM.so libGLESv1_CM.so.1 libGLESv1_CM.so.1.1.0 libGLESv2.so libGLESv2.so.2 libGLESv2.so.2.0.0 libGLESv2.so.2.1.0 libGLESv3.so libGLESv3.so.3 libgbm.so libgbm.so.1 libgbm.so.1.0.0 libmali.so libmali.so.1 libMaliOpenCL.so libOpenCL.so
  do
    sudo rm -fv ${LIB}
    sudo ln -sfv libMali.so ${LIB}
  done
  cd ../../../../
done
sudo chroot Arkbuild/ ldconfig -X

# Install meson
sudo chroot ${CHROOT_DIR}/ bash -c "git clone https://github.com/mesonbuild/meson.git && ln -s /meson/meson.py /usr/bin/meson"

# Build and install librga
sudo chroot ${CHROOT_DIR}/ bash -c "cd /home/ark &&
  git clone https://github.com/christianhaitian/linux-rga.git &&
  cd linux-rga &&
  git checkout 1fc02d56d97041c86f01bc1284b7971c6098c5fb &&
  meson build && cd build &&
  meson compile &&
  cp -r librga.so* /usr/lib/${ARCH}/ &&
  cd .. &&
  mkdir -p /usr/local/include/rga &&
  cp -f drmrga.h rga.h RgaApi.h RockchipRgaMacro.h /usr/local/include/rga/
  "

# Build and install libgo2
sudo chroot ${CHROOT_DIR}/ bash -c "cd /home/ark &&
  git clone https://github.com/OtherCrashOverride/libgo2.git &&
  cd libgo2 &&
  premake4 gmake &&
  make -j$(nproc) &&
  cp libgo2.so* /usr/lib/${ARCH}/ &&
  mkdir -p /usr/include/go2 &&
  cp -L src/*.h /usr/include/go2/
  "

# Snapshot the prepared chroot for the next build. --one-file-system keeps tar
# out of the live bind mounts even if an exclude is ever missed; the explicit
# excludes cover the kernel's own cached paths and the ccache bind.
if [ "$BIT" == "64" ]; then
  echo "Packing the prepared chroot for the build cache..."
  sudo umount ${CHROOT_DIR}/home/ark/Arkbuild_ccache 2>/dev/null
  if sudo tar --zstd -cf chroot-deps.tar.zst \
        --one-file-system \
        --exclude="${CHROOT_DIR}/lib/modules" \
        --exclude="${CHROOT_DIR}/lib/firmware" \
        --exclude="${CHROOT_DIR}/usr/lib/firmware" \
        --exclude="${CHROOT_DIR}/home/ark/Arkbuild_ccache" \
        --exclude="${CHROOT_DIR}/boot" \
        "${CHROOT_DIR}"; then
    bc_publish "$DEPS_CACHE_ASSET" chroot-deps.tar.zst
  else
    echo "Chroot pack failed - not publishing, build continues."
  fi
  rm -f chroot-deps.tar.zst
  sudo mount --bind ${PWD}/Arkbuild_ccache ${CHROOT_DIR}/home/ark/Arkbuild_ccache
fi

fi   # end of: prepared chroot came from the cache, or we just built one
