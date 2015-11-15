#!/bin/bash
env-update
source /etc/profile

echo "[*] Synching portage..."
emerge --sync --quiet
echo "[*] Setting clock to GMT..."
cp /usr/share/zoneinfo/GMT /etc/localtime
echo "[*] Downloading kernel sources..."
emerge gentoo-sources genkernel eudev device-mapper grub
USE="-dynamic" emerge cryptsetup
emerge ${OTHER_EBUILDS[@]}
echo "[*] Applying current kernel config."
zcat /proc/config.gz > $KERNEL_CONFIG
STATIC_CONFIG=( CONFIG_BLK_DEV_DM CONFIG_DM_CRYPT CONFIG_CRYPTO_SERPENT CONFIG_CRYPTO_SHA256 CONFIG_CRYPTO_BLOWFISH )
for CFG_ITEM in \${STATIC_CONFIG[@]}; do 
  sed -i s/\$CFG_ITEM=m/\$CFG_ITEM=y/ $KERNEL_CONFIG
done
genkernel --luks --kernel-config=$KERNEL_CONFIG all
# Setting root password with no echo.
echo -ne "$ROOT_PASSWORD\n$ROOT_PASSWORD\n"|passwd > /dev/null 2>&1