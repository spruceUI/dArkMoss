#!/bin/bash

# Stop the build when the 32-bit userland is not in the rootfs. "base" checks
# only what bootstrap_rootfs installs; "full" adds the rest of what a 32-bit
# RetroArch links, plus librga and libgo2.

if [[ "${BUILD_ARMHF}" == "y" ]]; then
  _armhf_dir=/usr/lib/arm-linux-gnueabihf
  _armhf_files="/lib/ld-linux-armhf.so.3 ${_armhf_dir}/libc.so.6 ${_armhf_dir}/libgcc_s.so.1"
  _armhf_files="${_armhf_files} ${_armhf_dir}/libstdc++.so.6 ${_armhf_dir}/libasound.so.2"
  _armhf_files="${_armhf_files} ${_armhf_dir}/libfreetype.so.6 ${_armhf_dir}/libudev.so.1"
  if [ "$1" != "base" ]; then
    _armhf_files="${_armhf_files} ${_armhf_dir}/libGLESv2.so.2 ${_armhf_dir}/libSDL2-2.0.so.0"
    _armhf_files="${_armhf_files} ${_armhf_dir}/librga.so ${_armhf_dir}/libgo2.so"
  fi
  _armhf_missing="$(sudo chroot Arkbuild/ bash -c "
    dpkg --print-foreign-architectures | grep -qx armhf || echo 'armhf foreign architecture'
    for f in ${_armhf_files}; do [ -e \$f ] || echo \$f; done")"
  if [ -n "${_armhf_missing}" ]; then
    echo "armhf userland incomplete ($1 check). Missing:"
    echo "${_armhf_missing}"
    exit 1
  fi
  echo "armhf userland verified ($1 check)."
fi
