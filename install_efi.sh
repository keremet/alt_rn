#!/bin/bash
set -e

if [ $# != 2 ] 
then
	echo "Help: $0 <device to install> <new host name>"
	echo "For example: $0 /dev/sda rn1076"
	exit 1
fi

DEVICE=$1
NEW_HOST_NAME=$2
MOUNT_DIR=/mnt

STEP_COLOR='\033[1;32m'
WARN_COLOR='\033[1;31m'
NO_COLOR='\033[0m'

function fill_part {
	echo -e "${STEP_COLOR}*** $1 ***${NO_COLOR}"
	set +e
	umount "$DEVICE$2" 2>/dev/null
	set -e
	unxz -T0 < $3.img.xz | dd of="$DEVICE$2" bs=1M status=progress conv=fsync
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
printf "UUID=$UUID\tnone\tswap\tsw\t0\t0\n" >> $MOUNT_DIR/etc/fstab

echo -e "${STEP_COLOR}*** Install GRUB, change host name ***${NO_COLOR}"
mkdir -p $MOUNT_DIR/boot/efi
mount "$DEVICE"1 $MOUNT_DIR/boot/efi
mount "$DEVICE"4 $MOUNT_DIR/var
mount "$DEVICE"5 $MOUNT_DIR/home
rm -r $MOUNT_DIR/home/user/.local/share/medit-1 $MOUNT_DIR/home/user/.cache/medit-1
sed -i "s/:rm=rn1084:/:rm=$NEW_HOST_NAME:/g" $MOUNT_DIR/etc/printcap
sed -i "s/^HOSTNAME=rn1084$/HOSTNAME=$NEW_HOST_NAME/g" $MOUNT_DIR/etc/sysconfig/network
sed -i "s/rn1084 rn1084$/$NEW_HOST_NAME/g" $MOUNT_DIR/etc/hosts
sed -i "s/rn1084 rn1084$/$NEW_HOST_NAME/g" $MOUNT_DIR/var/resolv/etc/hosts
echo "$NEW_HOST_NAME" > $MOUNT_DIR/etc/hostname
rm $MOUNT_DIR/etc/openssh/ssh_host_*
rm $MOUNT_DIR/var/spool/cups/c* $MOUNT_DIR/var/spool/cups/d* 
rm $MOUNT_DIR/var/log/journal/a590e2c236ea43c7ce0bc9db61c7035f/*
#For ProBook 6470b https://rockhopper.dk/linux/hardware/uefi-booting-arch-linux-on-a-hp-probook-6360b/
#grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=altlinux --recheck


mount --bind /dev "$MOUNT_DIR"/dev
mount --bind /sys "$MOUNT_DIR"/sys
mount --bind /proc "$MOUNT_DIR"/proc
rm -r $MOUNT_DIR/etc/grub.d/20_linux_xen $MOUNT_DIR/etc/grub.d/3* $MOUNT_DIR/etc/grub.d/40*
sed -i 's/linux\t\${rel_dirname}\/${basename} root=\${linux_root_device_thisversion} ro \${args}/linuxefi\t\${rel_dirname}\/\${basename} root=\${linux_root_device_thisversion} ro \${args}/g' $MOUNT_DIR/etc/grub.d/10_linux
sed -i 's/initrd\t\$(echo \$initrd_path)/initrdefi\t\$(echo \$initrd_path)/g' $MOUNT_DIR/etc/grub.d/10_linux
chroot "$MOUNT_DIR" grub-install --root-directory=/ --no-nvram $DEVICE
chroot "$MOUNT_DIR" update-grub
chroot "$MOUNT_DIR" mklocatedb
mkdir -p $MOUNT_DIR/boot/efi/EFI/BOOT
cp $MOUNT_DIR/boot/efi/EFI/altlinux/grubx64.efi $MOUNT_DIR/boot/efi/EFI/BOOT/BOOTX64.EFI
cp $MOUNT_DIR/boot/efi/EFI/altlinux/grub.cfg    $MOUNT_DIR/boot/efi/EFI/BOOT/
umount "$MOUNT_DIR"/dev
umount "$MOUNT_DIR"/sys
umount "$MOUNT_DIR"/proc

umount $MOUNT_DIR/home
umount $MOUNT_DIR/var
umount $MOUNT_DIR/boot/efi
umount $MOUNT_DIR


echo -e "${STEP_COLOR}*** ALT-RN has been successfully installed ***${NO_COLOR}"
echo -e "Press ${STEP_COLOR}ALT+CTRL+DEL${NO_COLOR} to reboot or ${STEP_COLOR}Enter${NO_COLOR} to open a shell prompt"
read
