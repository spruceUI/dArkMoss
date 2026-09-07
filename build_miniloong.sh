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
# Set chipset in environment variable
export CHIPSET=rk3566
export UNIT=miniloong
export UNIT_DTB=${CHIPSET}-${UNIT}

# Load shared utilities (if any)
source ./utils.sh

# Let's make sure necessary tools are available
source ./prepare.sh

# Step-by-step build process
source ./setup_partition-rk3566.sh
source ./bootstrap_rootfs-rk3566.sh
source ./build_kernel-rk3566.sh
source ./build_deps.sh

# --- dArkMoss strip -------------------------------------------------------
# spruce is the frontend and ships its own emulators, SDL, input and helper
# tools on TF2, so none of the upstream dArkOS emulator/frontend builds are
# wanted here. Dropping them turns a multi-hour compile into debootstrap +
# kernel + assembly. Left commented rather than deleted so the exact upstream
# set is visible and any single one is trivial to re-enable if assembly turns
# out to need it.
# --- port runtime: keep these, PortMaster needs them -----------------------
# dArkOS builds its own SDL2 from christianhaitian/rk3566_core_builds and
# installs it AS the system libSDL2-2.0.so.0. That build is made for this Mali
# blob, and it is what every dArkOS port runs against. Stock Debian's SDL2 is
# not a substitute: it links libwayland-egl and asks for a desktop GL config the
# blob does not advertise - the same wall PyUI had to code around with an
# explicit ES profile. Ports link SDL2 themselves and cannot be patched one by
# one, so the fix has to be the library.
source ./build_sdl2.sh
#source ./build_ppssppsa.sh
#source ./build_ppsspp-2021sa.sh
#source ./build_duckstationsa.sh
#source ./build_mupen64plussa.sh
#source ./build_gzdoom.sh
#source ./build_lzdoom.sh
#source ./build_retroarch.sh
#source ./build_retrorun.sh
#source ./build_yabasanshirosa.sh
#source ./build_mednafen.sh
#source ./build_ecwolfsa.sh
#source ./build_hypseus-singe.sh
#source ./build_openbor.sh
#source ./build_solarus.sh
#source ./build_scummvmsa.sh
#source ./build_fake08.sh
#source ./build_xroar.sh
#source ./build_mvem.sh
#source ./build_bigpemu.sh
#source ./build_ogage.sh
# oga_controls is what ArkOS ports call to read the pad.
source ./build_ogacontrols.sh
# --- end port runtime ------------------------------------------------------
#source ./build_351files.sh
#source ./build_filemanager.sh
#source ./build_filebrowser.sh
# gptokeyb maps the pad to keys for ports that want a keyboard; drmtool is
# called by ports that take the display directly. Both are standard ArkOS port
# furniture and cheap to build.
source ./build_gptokeyb.sh
source ./build_drmtool.sh
#source ./build_image-viewer.sh
#source ./build_emulationstation-rk3566.sh
#source ./build_linapple.sh
#source ./build_applewinsa.sh
#source ./build_piemu.sh
#source ./build_ti99sim.sh
#source ./build_gametank.sh
#source ./build_openmsxsa.sh
#source ./build_flycastsa.sh
#source ./build_dolphinsa.sh
#source ./build_ffmpeg.sh
#source ./build_sdljoytest.sh
#source ./build_controllertester.sh
#source ./build_batteryplus.sh
#source ./build_drastic.sh
#if [[ "${BUILD_BLUEALSA}" == "y" ]]; then
#  source ./build_bluealsa.sh
#fi
#if [[ "${BUILD_KODI}" == "y" ]]; then
#  source ./build_kodi.sh
#fi
# --- end dArkMoss strip ---------------------------------------------------
source ./finishing_touches-rk3566.sh
source ./setup_spruce_handoff-rk3566.sh
source ./cleanup_filesystem.sh
source ./write_rootfs-rk3566.sh
source ./clean_mounts.sh
source ./create_image.sh
) 2>&1 | tee -a build.log

echo "Miniloong Pocket 1 build completed. Final image is ready."
