#!/bin/bash

# dArkMoss: drop the build toolchain that the needed_packages lists put back, and
# whatever only it pulled in. armhf runtime libraries stay; only their -dev chain goes.

echo -e "Purging build-only packages...\n\n"

_keep_lists="needed_packages.txt"
[[ "${BUILD_ARMHF}" == "y" ]] && _keep_lists="${_keep_lists} needed_packages32.txt"
[[ "${BUILD_BLUEALSA}" == "y" ]] && _keep_lists="${_keep_lists} bluetooth_needed_packages.txt"
for _list in ${_keep_lists}; do
  _arch=""
  [[ "${_list}" == "needed_packages32.txt" ]] && _arch=":armhf"
  grep -v '^#' "${_list}" | sed "/^$/d; s/\$/${_arch}/"
done | grep -vxFf darkmoss_purge_packages.txt | sudo tee Arkbuild/tmp/darkmoss_keep >/dev/null
sudo cp darkmoss_purge_packages.txt Arkbuild/tmp/darkmoss_purge

sudo chroot Arkbuild/ bash -s <<'PURGE'
installed() { dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null | grep -qx installed; }

for p in $(cat /tmp/darkmoss_keep); do installed "$p" && echo "$p"; done > /tmp/darkmoss_keep_before

dpkg-query -W -f='${db:Status-Status} ${Package}:${Architecture}\n' | awk '$1=="installed"{print $2}' \
  | grep ':armhf$' | grep -vE -- '-dev:armhf$|^(cross-exe-wrapper|girepository-tools|gir1\.2-[^:]*|pkgconf|pkgconf-bin):armhf$' \
  | xargs -r apt-mark manual >/dev/null
installed patch && apt-mark manual patch >/dev/null

PURGE_LIST=""
for p in $(cat /tmp/darkmoss_purge); do installed "$p" && PURGE_LIST="${PURGE_LIST} $p"; done
DEBIAN_FRONTEND=noninteractive apt-get -y purge --auto-remove ${PURGE_LIST}
apt-get -y clean
locale-gen

rm -rf /meson /usr/bin/meson /root/.cache

for p in $(cat /tmp/darkmoss_keep_before); do installed "$p" || echo "$p"; done > /tmp/darkmoss_lost
PURGE
_lost="$(cat Arkbuild/tmp/darkmoss_lost)"
sudo rm -f Arkbuild/tmp/darkmoss_keep Arkbuild/tmp/darkmoss_keep_before Arkbuild/tmp/darkmoss_purge Arkbuild/tmp/darkmoss_lost
if [ -n "${_lost}" ]; then
  echo "darkmoss_purge removed needed packages:"
  echo "${_lost}"
  exit 1
fi
