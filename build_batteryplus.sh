#!/bin/bash

# Building battery plus by Mikhailzrick (https://github.com/Mikhailzrick/knubat.components/tree/main/BatteryPlus)
if [ -f "Arkbuild_package_cache/${CHIPSET}/batteryplus.tar.gz" ] && [ "$(cat Arkbuild_package_cache/${CHIPSET}/batteryplus.commit)" == "$(curl -s 'https://api.github.com/repos/Mikhailzrick/knubat.components/commits?path=BatteryPlus/batteryplus.cpp&per_page=1' | jq -r '.[0].sha')" ]; then
    sudo tar -xvzpf Arkbuild_package_cache/${CHIPSET}/batteryplus.tar.gz
else
	call_chroot "cd /home/ark/${CHIPSET}_core_builds &&
	  wget -t 5 -T 30 --no-check-certificate https://github.com/Mikhailzrick/knubat.components/raw/refs/heads/main/BatteryPlus/batteryplus.cpp &&
	  g++ -O3 -flto -std=gnu++20 -Wall -Wextra -pedantic batteryplus.cpp -o batteryplus &&
	  strip batteryplus &&
	  mv batteryplus /usr/local/bin/batteryplus &&
	  chmod 777 /usr/local/bin/batteryplus &&
	  rm batteryplus.cpp &&
	  rm -f wget-log*
	  "
	if [ -f "Arkbuild_package_cache/${CHIPSET}/batteryplus.tar.gz" ]; then
	  sudo rm -f Arkbuild_package_cache/${CHIPSET}/batteryplus.tar.gz
	fi
	if [ -f "Arkbuild_package_cache/${CHIPSET}/batteryplus.commit" ]; then
	  sudo rm -f Arkbuild_package_cache/${CHIPSET}/batteryplus.commit
	fi
	sudo curl -s 'https://api.github.com/repos/Mikhailzrick/knubat.components/commits?path=BatteryPlus/batteryplus.cpp&per_page=1' | jq -r '.[0].sha' > Arkbuild_package_cache/${CHIPSET}/batteryplus.commit
	sudo tar -czpf Arkbuild_package_cache/${CHIPSET}/batteryplus.tar.gz Arkbuild/usr/local/bin/batteryplus
fi
sudo cp batteryplus/scripts/batteryplus.sh Arkbuild/usr/local/bin/
sudo cp batteryplus/systemd/* Arkbuild/etc/systemd/system/
sudo mkdir -p Arkbuild/etc/batteryplus
sudo cp --remove-destination batteryplus/config/batteryplus.conf Arkbuild/etc/batteryplus/
sudo mkdir -p Arkbuild/home/ark/.config
echo "Pmic" | sudo tee Arkbuild/home/ark/.config/.BRMODE
sudo chmod 777 Arkbuild/usr/local/bin/*
call_chroot "chmod 644 /etc/systemd/system/batteryplus.service"
call_chroot "systemctl enable batteryplus"
