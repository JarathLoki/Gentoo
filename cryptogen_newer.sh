#!/bin/bash
#
#  Encrypted Gentoo Installator | 2009 by oozie | http://blog.ooz.ie/
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  Modified for modern Gentoo systems by Jarath Loki c.2015
#
LICENSE="Copyright (C) 2009 by Slawek Ligus. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. The name of the author may not be used to endorse or promote 
   products derived from this software without specific prior written 
   permission. 
 
THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR 
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS 
BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT 
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
###

### Config variables ###
CRYPTO_MODULES=( "dm-crypt" "dm-mod" "serpent" "sha256" "blowfish" )
SYNC="rsync://rsync.gentoo.org/gentoo-portage"
MAKE_OPTS=( -j2 )
USE_FLAGS=( ipv6 dvd alsa cdr opengl X jpeg png network gif xulrunner hal pdf aalib svg dbus python )
OTHER_EBUILDS=( vim links dhcpcd )
########################

### Do not edit below this line. ###
MAPPERROOT=/dev/mapper/root
IFS="
"
OUTPUT=$(mktemp /tmp/cryptogen.out.XXXXX)
CONFIG=$(mktemp /tmp/cryptogen.conf.XXXXX)
LOGFILE=$(mktemp /tmp/cryptogen.log.XXXXX)
NEWROOT=/mnt/gentoo
CRYPTSETUP="/sbin/cryptsetup"
COPYRIGHT=" < (c) 2009 by oozie <root ooz ie> | http://blog.ooz.ie > "
case $(arch) in
  x86_64) ARCH=amd64
  ;;
  i686) ARCH=x86
  ;;
  i586) ARCH=x86
  ;;
  i486) ARCH=x86
  ;;
  *) ARCH=$ARCH
  ;;
esac
KERNEL_CONFIG="/usr/share/genkernel/arch/$ARCH/kernel-config-2.6"
 
function GracefulExit() {
  # Exit gracefully and clean up config files.
  EXITCODE=$1
  # Display second argument to the function as exit message.
  if [ "$2" != "" ]; then 
    MESSAGE=$2
  else
    MESSAGE=$COPYRIGHT
  fi
  echo
  echo $MESSAGE
  rm -f $OUTPUT $CONFIG $OUTPUT.error
  # Pass first argument as exit code to environment.
  exit $EXITCODE
}

function Intro() {
  function ShowLicense() {
    # Show the license.
    MESSAGE="$LICENSE
  
    Do you agree to the terms of the license?"
  
    dialog --yesno "$MESSAGE" 33 75
  }
  # Show the welcome message.
  MESSAGE="Welcome to CryptoGen (0x01)
 
  This will install base Gentoo Linux onto an encrypted partition.
  Probably all of the data on your hard drive(s) will be lost as
  a result. You need to understand the risk and agree to terms
  of the license if you wish to continue.
  "
  dialog --msgbox "$MESSAGE" 11 75

  # License.
  # Quit if the user rejects the terms.
  ShowLicense || GracefulExit 1
}

function Directories() {
  #Make the directories as it clearly wasn't working now
  mkdir /mnt/gentoo
  mkdir /mnt/gentoo/proc
  mkdir /mnt/gentoo/dev
}

function AskHowToPartition() {
  dialog --menu "How to partition the disk?" 14 60 10 \
                "fdisk" "Use simple fdisk." \
	        "cfdisk" "Use ncurses cfdisk." \
	        "other" "Enter bash, do partitioning and come back." \
	        "done" "Partitioning is done. Proceed." \
	        2>$OUTPUT || GracefulExit 1
		     
}

function GetHardDrives() {
  # List visible hard drives.
  local -i INDEX
  local -a MENU_PARAMS
  DISK_ENTRIES=( $(fdisk -l|sed -n '/Disk \//p') )
  for DISK_ENTRY in ${DISK_ENTRIES[@]}; do
    DISK=${DISK_ENTRY%:*}
    DISK_FILE=${DISK#* }
    DISK_SIZE=${DISK_ENTRY#*: }
    MENU_PARAMS[$[INDEX]]=$DISK_FILE
    MENU_PARAMS[$[INDEX+1]]=$DISK_SIZE
    let INDEX=$[INDEX+2]
  done
  dialog --menu "Select Drive" 10 50 10 ${MENU_PARAMS[@]} \
    2> $OUTPUT || GracefulExit 1
}

function Partitioning(){
  # Partition with fdisk.
  METHOD=$1
 
  case "$METHOD" in
    "fdisk") 
      GetHardDrives 
      fdisk $(cat $OUTPUT)
    ;;
    "cfdisk") 
      GetHardDrives 
      cfdisk $(cat $OUTPUT)
    ;;
    "other")
      echo " Partition the hard drive on your own and type exit to get back."
      bash
    ;;
    "done") echo "done"
      # Proceeding.
      echo
    ;;
    *) 
      # Try again.
      AskHowToPartition
    ;;
  esac
 }

function SelectMountpoints() {
  # List partitions of the selected hard drive.
  local -i INDEX
  local -a MENU_PARAMS

  function DisplayMenu() {
    TITLE=$1
    INDEX=0
    MENU_PARAMS=()
    for PARTITION_ENTRY in ${PARTITION_ENTRIES[@]}; do
      PARTITION_NAME=$PARTITION_ENTRY
      PARTITION_SIZE=$(fdisk -s $PARTITION_NAME)
      MENU_PARAMS[$INDEX]=$PARTITION_NAME
      MENU_PARAMS[$[INDEX+1]]=$PARTITION_SIZE
      let INDEX=$INDEX+2
    done
    
    dialog --menu "$TITLE" 10 50 10 ${MENU_PARAMS[@]} \
      2> $OUTPUT || GracefulExit 1
  }

  export PARTITION_ENTRIES=( $(fdisk -l |gawk '/^\//{print $1}') )
  DisplayMenu "Select /boot partition"
  BOOT=$(cat $OUTPUT)
  echo "BOOT=$BOOT" >> $CONFIG

  export PARTITION_ENTRIES=( $(fdisk -l | gawk -v boot=$BOOT \
                                          '/^\//{if ($1!=boot) print $1}') )
  DisplayMenu "Select / (root) partition"
  ROOT=$(cat $OUTPUT)
  echo "ROOT=$ROOT" >> $CONFIG

}

function MirrorSelect() {
  # Tell user to select mirrors.
  function AreYouSure() {
    MESSAGE="You did not select any mirrors. In order to continue you must select at least one.\nDo you want to continue?"
    dialog --yesno $MESSAGE 7 60
    return $?
  }
  MIRRORS=$(mirrorselect -i -o) || (AreYouSure && MirrorSelect || GracefulExit 1)
  echo $MIRRORS >> $CONFIG
}

function GetHostname() {
  # Takes hostname.
  dialog --inputbox "Enter hostname:" 8 30 2>$OUTPUT
  echo "NEWHOSTNAME=$(cat $OUTPUT)" >> $CONFIG
}

function GetPasswords() {
  # Get root password and LUKS passphrase for the encrypted partition.
    function TakePassword() {
      PASSNAME=$1
      CONFVAR=$2
      dialog --passwordbox "Enter $PASSNAME:" 10 30 2>$OUTPUT || GracefulExit 1
      PASS1=$(cat $OUTPUT)
      dialog --passwordbox "Confirm $PASSNAME:" 10 30 2>$OUTPUT || GracefulExit 1
      PASS2=$(cat $OUTPUT)
      if [ "$PASS1" != "$PASS2" ]; then
        dialog --msgbox "Passwords do not match. Try again." 5 40
        TakePassword "$PASSNAME" "$CONFVAR"
      else
        echo "$CONFVAR=\"$PASS1\"" >> $CONFIG
      fi
 
    }
  TakePassword "root password" ROOT_PASSWORD
  TakePassword "LUKS passphrase" LUKS_PASSPHRASE
}

function LoadModules() {
  # Load cryptographic modules.
  unset IFS
  declare -i PERCENTAGE=0
  WIDTH=50
  HEIGHT=10
  STEP_PERCENT=$[100/${#CRYPTO_MODULES[@]}]
  for MODULE in ${CRYPTO_MODULES[@]}
  do
    echo $PERCENTAGE| dialog --gauge "Loading module $MODULE..." $HEIGHT $WIDTH
    modprobe $MODULE || GracefulExit 3 "Could not load module $MODULE. Exiting."
    let PERCENTAGE=$PERCENTAGE+$STEP_PERCENT
    echo $PERCENTAGE| dialog --gauge "Loading module $MODULE... success." $HEIGHT $WIDTH
    sleep 0.1
  done

}

function SetupCryptRoot() {
  ## luksFormat $ROOT

  echo -e "$LUKS_PASSPHRASE"|$CRYPTSETUP \
  -v --cipher serpent-cbc-essiv:sha256 --key-size 256 luksFormat $ROOT \
  2> $LOGFILE | dialog --infobox "Formatting LUKS partition $ROOT" 3 50

  ## Check if it is a valid LUKS partition.
  $CRYPTSETUP isLuks $ROOT || GracefulExit "Could not luksFormat $ROOT."

  ## luksOpening $ROOT
  (echo -e "$LUKS_PASSPHRASE"|$CRYPTSETUP luksOpen $ROOT root 2>$LOGFILE ) \
  | dialog --infobox "LUKS opening partition $ROOT" 3 50
  test ! -e $MAPPERROOT && GracefulExit 3 "Could not open $MAPPERROOT"
  sleep 3

  ## Creating Filesystem on $MAPPERROOT
  mkfs.ext4 -j -m 1 $MAPPERROOT 2>$LOGFILE \
  || GracefulExit 3 "mkfs.ext4 failed."

  ## Mounting to $NEWROOT
  (mount -t ext4 $MAPPERROOT $NEWROOT 2>$LOGFILE) \
  | dialog --infobox "Mounting root on $NEWROOT" 3 50
  test "$(mount|grep $MAPPERROOT)" == "" && GracefulExit 3 "Mounting failed."

  # Clear the logfile if there were no fatal errors.
  echo -n > $LOGFILE
}

function DownloadBase() {
  ## Download stage 3 and latest portage and unpack it.
  MIRRORS=( $GENTOO_MIRRORS )
  # TODO: Pick a mirror with best response time.
  #AUTOBUILDS= "$MIRROR""releases/$ARCH/autobuilds/"
  MIRROR=${MIRRORS[0]}
  AUTOBUILDS="$MIRROR""releases/$ARCH/autobuilds/"
  LATEST_PORTAGE="$MIRROR""releases/snapshots/current/portage-latest.tar.bz2"
  LATEST_STAGE3=$(links -source $AUTOBUILDS/latest-stage3-amd64-hardened.txt | egrep "^20[0-9]{6}/stage3-$(arch)")
  # Changed from AUTOBUILDS/latest-stage3.txt
  # changed from LATEST-STAGE3$(blah....) links -source to curl -s "${MIRROR}/releases/
  # Downloading latest stage3.
  # TODO: Check .DIGESTS file.
  #wget -P $NEWROOT "$AUTOBUILDS""$LATEST_STAGE3"
  #mkdir /mnt/gentoo
  mkdir /mnt/gentoo/proc
  mkdir /mnt/gentoo/dev
  mkdir /mnt/gentoo/etc
  mkdir /mnt/gentoo/usr
  mkdir /mnt/gentoo/boot
  mkdir /mnt/gentoo/tmp/
  mkdir /mnt/gentoo/boot/grub
  mkdir /mnt/gentoo/bin
  mkdir /mnt/gentoo/sbin
  
  cd /mnt/gentoo
  wget http://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-hardened/stage3-amd64-hardened-20151112.tar.bz2
  # Unpacking stage3. Call the shell to try to untar the unit
  #/bin/sh -c tar xvjpf $NEWROOT/stage3-'*'.tar.bz2 -C $NEWROOT | dialog --infobox "Unpacking stage3..." 3 30
  tar xvjpf /mnt/gentoo/stage3-amd64-hardened-20151112.tar.bz2 -C /mnt/gentoo | dialog --infobox "Unpacking stage3..." 3 30
  # Mounting virtual filesystems
  #mount -t proc none /mnt/gentoo/proc
  #mount -o bind /dev /mnt/gentoo/dev
  cp /etc/resolv.conf /mnt/gentoo/etc/resolv.conf
  mount -t proc none /mnt/gentoo/proc 
  mount -o bind /dev /mnt/gentoo/dev

  # Downloading latest portage.
  wget -P $NEWROOT "$LATEST_PORTAGE"
  wget -P $NEWROOT "$LATEST_PORTAGE".md5sum
  cd /mnt/gentoo
  tar xjf $NEWROOT/portage-latest.tar.bz2 -C $NEWROOT/usr | \
  dialog --infobox "Unpacking latest portage..." 3 30
  # Removing archives.
  rm -f $NEWROOT/*.tar.bz2
}


function BaseSetup() {

  # Sets up basic configuration files.
  #################################

  # Formatting $BOOT.
  mkfs.ext2 $BOOT
  # Mounting $BOOT.
  mount $BOOT $NEWROOT/boot

  # Setting up make.conf
  #changed from $NEWROOT/ect/make.conf
  cat << _EOF_ > /mnt/gentoo/etc/make.conf
CFLAGS="-O2 -pipe"
# Use the same settings for both variables
CXXFLAGS="\${CFLAGS}"
MAKEOPTS="${MAKE_OPTS[@]}"
USE="${USE_FLAGS[@]}"

SYNC=$SYNC
GENTOO_MIRRORS="$GENTOO_MIRRORS"
_EOF_

# Modifying up /etc/fstab
#changed from $NEWROOT/etc/fstab
  sed -i -e "s:/dev/BOOT:$BOOT:" -e "s:/dev/ROOT:$MAPPERROOT:" -e "/\/dev\/SWAP/d" /mnt/gentoo/etc/fstab

# Setting hostname.
#changed from $NEWROOT/etc/conf.d/hostname
  sed -ie s/localhost/$NEWHOSTNAME/ /mnt/gentoo/etc/conf.d/hostname

# Executing a chrooted batch job.
touch $NEWROOT/tmp/batch.sh
cat << _EOF_ > $NEWROOT/tmp/batch.sh
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
_EOF_
  chmod +x $NEWROOT/tmp/batch.sh
  chroot $NEWROOT /tmp/batch.sh
  rm -f $NEWROOT/tmp/batch.sh
}

function InstallBootloader() {
  # Installing bootloader WARNING!!!!!!!! The wildcard is broken!
  ln $NEWROOT/boot/kernel-genkernel-* $NEWROOT/boot/cryptkernel
  ln $NEWROOT/boot/initramfs-genkernel-* $NEWROOT/boot/cryptramfs

  DEVICE_MAP=$NEWROOT/tmp/device.map
  chroot $NEWROOT grub --no-floppy --device-map=/tmp/device.map < /dev/null 2>/dev/null
  
  declare -i INDEX
  declare -a MENU_PARAMS=()
  declare -a PART_MAPPING=()
  INDEX=0
  while read DEV_ENTRY
  do
    TMP=( $DEV_ENTRY )
    BIOS_NAME=${TMP[0]}
    DEV_NAME=${TMP[1]}
    TMP2="MBR of $DEV_NAME"
    MENU_PARAMS[$[INDEX]]=$BIOS_NAME
    MENU_PARAMS[$[INDEX+1]]=$TMP2
    let INDEX=$[INDEX+2]
    for DEVPART_NAME in "$DEV_NAME"?*; do
      PART_NUM=${DEVPART_NAME:${#DEV_NAME}}
      BIOS_NUM=$[PART_NUM-1]
      BIOSPART_NAME=$(echo $BIOS_NAME|sed s/\)/,$BIOS_NUM\)/)
      test "$DEVPART_NAME" == "$BOOT" && BIOSBOOT="$BIOSPART_NAME"
      TMP2="Boot sector of $DEVPART_NAME"
      MENU_PARAMS[$[INDEX]]=$BIOSPART_NAME
      MENU_PARAMS[$[INDEX+1]]=$TMP2
      let INDEX=$[INDEX+2]
    done
  done < $DEVICE_MAP
  dialog --menu "Where do you want to install GRUB?" 15 40 15 "${MENU_PARAMS[@]}" 2>$OUTPUT
  GRUB_PART=$(cat $OUTPUT)

touch $NEWROOT/boot/grub/menu.lst
cat << _EOF_ > $NEWROOT/boot/grub/menu.lst
default 0
timeout 3
splashimage=$BIOSBOOT/grub/splash.xpm.gz

title Encrypted Gentoo Linux
root $BIOSBOOT
kernel /cryptkernel vga=791 crypt_root=$ROOT root=/dev/ram0 real_root=$MAPPERROOT splash=verbose console=tty1
initrd /cryptramfs

_EOF_
  cp /etc/mtab $NEWROOT/etc/mtab
  chroot $NEWROOT /bin/umount /boot
  chroot $NEWROOT /bin/mount $BOOT /boot
  chroot $NEWROOT /sbin/grub-install $GRUB_PART
}

function Main() {
  # Main function.
  test "$UID" -eq "0" || GracefulExit 2 "Only root can run this program."
  #Make /mnt/gentoo /mnt/gentoo/proc and /mnt/gentoo/dev Make the directories function
  Directories
  # Introduce.
  Intro
  # Prompt the user on how to proceed.
  AskHowToPartition 2>$OUTPUT
  # Partitioning.
  Partitioning $(cat $OUTPUT)
  ## Select mountpoints.
  SelectMountpoints
  ## Select Mirrors.
  MirrorSelect
  ## Ask for hostname.
  GetHostname
  ## Get passwords.
  GetPasswords
  ## Load modules.
  LoadModules
  ## Read in the config file
  . $CONFIG
  ## Cryptformat $ROOT and luksOpen it.
  SetupCryptRoot
  ## Download stage 3 and latest portage and unpack it.
  DownloadBase
  ## Set up basic files.
  BaseSetup
  ## Install the bootloader
  InstallBootloader
}

# Start.
Main
echo
echo "Encrypted Gentoo installed on $ROOT."
