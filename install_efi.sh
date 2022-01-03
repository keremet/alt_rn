#!/bin/bash
set -e

if [ $# != 1 ] 
then
	echo "Help: $0 <device to install>"
	echo "For example: $0 /dev/sda"
	exit 1
fi

export DEVICE=$1
export MOUNT_DIR=/mnt

STEP_COLOR='\033[1;32m'
WARN_COLOR='\033[1;31m'
NO_COLOR='\033[0m'

function fill_part {
	echo -e "${STEP_COLOR}*** $1 ***${NO_COLOR}"
	set +e
	umount "$DEVICE$2" 2>/dev/null
	set -e
	unxz < $3.img.xz | dd of="$DEVICE$2" bs=1M status=progress conv=fsync
	e2fsck -f "$DEVICE$2"
	resize2fs "$DEVICE$2"
	e2fsck "$DEVICE$2"
}

parted $DEVICE print
[ "$?" -ne 0 ] && exit 1

echo -en "${WARN_COLOR}All data on the disk will be destroyed.${NO_COLOR} "
read -p "Are you sure you want to install ALT-RN on this disk (y/n)? " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || exit 1 


echo -e "${STEP_COLOR}*** Creating partitions and file systems ***${NO_COLOR}"

dd if=/dev/zero of=$DEVICE bs=1M count=3
parted $DEVICE mktable gpt 2>&1 | grep -v /etc/fstab
parted -a optimal $DEVICE mkpart fat32 2MiB 261MiB 2>&1 | grep -v /etc/fstab
parted $DEVICE set 1 esp on 2>&1 | grep -v /etc/fstab
parted -a optimal $DEVICE mkpart primary ext4 261MiB 60GB 2>&1 | grep -v /etc/fstab
parted -a optimal $DEVICE mkpart primary linux-swap 117186560s 150740991s 2>&1 | grep -v /etc/fstab
#150740992+20*1024*1024*1024/512-1
parted -a optimal $DEVICE mkpart primary ext4 150740992s 192684031s 2>&1 | grep -v /etc/fstab
parted -a optimal $DEVICE mkpart primary ext4 192684032s 100% 2>&1 | grep -v /etc/fstab


parted $DEVICE print                           

echo -e "${STEP_COLOR}*** UEFI ***${NO_COLOR}"
set +e
umount "$DEVICE"1 2>/dev/null
set -e
mkfs.fat -F 32 "$DEVICE"1

fill_part / 2 root

echo -e "${STEP_COLOR}*** Swap ***${NO_COLOR}"
set +e
umount "$DEVICE"3 2>/dev/null
set -e
mkswap "$DEVICE"3

fill_part /var 4 var
fill_part /home 5 home


mount "$DEVICE"2 $MOUNT_DIR

##Настроить подключение свопа при загрузке
sed -i '/swap/d' $MOUNT_DIR/etc/fstab
sed -i '/\/boot\/efi/d' $MOUNT_DIR/etc/fstab
UUID=`blkid --match-tag UUID -o value "$DEVICE"3`
printf "UUID=$UUID\tnone\tswap\tsw\t0\t0" >> $MOUNT_DIR/etc/fstab

echo -e "${STEP_COLOR}*** Install GRUB ***${NO_COLOR}"
mkdir -p $MOUNT_DIR/boot/efi
mount "$DEVICE"1 $MOUNT_DIR/boot/efi
mount "$DEVICE"4 $MOUNT_DIR/var
grub-install --root-directory=$MOUNT_DIR --bootloader-id=altlinux $DEVICE

mount --bind /dev "$MOUNT_DIR"/dev
mount --bind /sys "$MOUNT_DIR"/sys
mount --bind /proc "$MOUNT_DIR"/proc
chroot "$MOUNT_DIR" update-grub
umount "$MOUNT_DIR"/dev
umount "$MOUNT_DIR"/sys
umount "$MOUNT_DIR"/proc

umount $MOUNT_DIR/var
umount $MOUNT_DIR/boot/efi
umount $MOUNT_DIR


echo -e "${STEP_COLOR}*** ALT-RN has been successfully installed ***${NO_COLOR}"

read -p "Do you want to reboot now(y/n)? " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] && reboot
