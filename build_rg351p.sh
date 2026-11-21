#!/bin/bash
#exec 3>&1 4>&2
#trap 'exec 2>&4 1>&3' 0 1 2 3
#exec 1>build.log 2>&1
#set -e
if [ -f "build.log" ]; then
  ext=1
  while true
  do
    if [ -f "build.log.${ext}" ]; then
      let ext=ext+1
	  continue
	else
      mv build.log build.log.${ext}
	  break
	fi
  done
fi
(
# dArkMoss for the Anbernic RG351P on the rg351 kernel the G350, A10 Mini, Mini M
# and V10 use, with that kernel's own rk3326-rg351p-linux.dts, and the RG351
# family U-Boot (RG351MP-u-boot's rg351p-uboot.dts). Built like the V10.
# Set chipset in environment variable
export CHIPSET=rk3326
export UNIT=rg351p

# Load shared utilities (if any)
source ./utils.sh

# Let's make sure necessary tools are available
source ./prepare.sh

# Step-by-step build process
source ./setup_partition.sh
source ./bootstrap_rootfs.sh
source ./verify_armhf.sh base
source ./image_setup.sh
source ./build_kernel.sh
source ./build_deps.sh
# dArkMoss: spruce brings the frontend and emulators on TF2, so only the port
# runtime is built here - see build_rgb30.sh for what upstream builds and why.
source ./build_sdl2.sh
source ./build_sdl3.sh
if [[ "${BUILD_ARMHF}" == "y" ]]; then
  source ./build_arm32_libs.sh
fi
source ./build_ogacontrols.sh
source ./build_gptokeyb.sh
source ./build_drmtool.sh
# BatteryPlus in pmic mode: the kernel gauge %, smoothed.
source ./build_batteryplus.sh
source ./finishing_touches.sh
source ./setup_spruce_handoff.sh
source ./cleanup_filesystem.sh
source ./verify_armhf.sh full
source ./build_update.sh
source ./write_rootfs.sh
source ./clean_mounts.sh
source ./create_image.sh
) 2>&1 | tee -a build.log

echo "RG351P build completed. Final image is ready."

