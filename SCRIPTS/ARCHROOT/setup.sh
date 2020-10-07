#!/bin/bash

set -eux

SETUP_DISK=nvme0n1
SETUP_MIRROR='http://mirrors.kernel.org/archlinux/$repo/os/$arch'

# update system date/time

timedatectl set-ntp true

# partition disk

parted -s /dev/"${SETUP_DISK}" -- \
  mklabel gpt \
  mkpart primary 0% 1GiB \
  mkpart primary 1GiB 17GiB \
  mkpart primary 17GiB 100% \
  set 1 esp on \
  name 1 esp \
  name 2 cryptswap \
  name 3 cryptroot

partprobe /dev/"${SETUP_DISK}"

# format EFI partition

mkfs.fat -n ESP -F 32 /dev/"${SETUP_DISK}p1"

# create & format encrypted root partition

cryptsetup luksFormat /dev/"${SETUP_DISK}p3" --type luks --cipher aes-xts-plain64 --key-size 256 --hash sha256 --use-urandom --verify-passphrase --batch-mode
cryptsetup open /dev/"${SETUP_DISK}p3" root --type luks --allow-discards
mkfs.btrfs -f -L root /dev/mapper/root

mkdir /tmp/root
mount -o defaults,noatime,compress=zstd /dev/mapper/root /tmp/root
btrfs subvolume create /tmp/root/@
btrfs subvolume create /tmp/root/@home
btrfs subvolume create /tmp/root/@pkg
btrfs subvolume create /tmp/root/@log

# setup encrypted swap partition

dd if=/dev/urandom of=/tmp/root/swap.key bs=1024 count=4
chmod 0400 /tmp/root/swap.key
cryptsetup open /dev/"${SETUP_DISK}p2" swap --type plain --cipher aes-xts-plain64 --key-size 256 --key-file /tmp/root/swap.key  --batch-mode
mkswap -L swap /dev/mapper/swap

# mount filesystems

mount -o defaults,noatime,subvol=@ /dev/mapper/root /mnt
mkdir -p /mnt/{home,boot/esp,var/log,var/cache/pacman/pkg}
mount -o defaults,noatime,subvol=@home /dev/mapper/root /mnt/home
mount -o defaults,noatime,subvol=@pkg /dev/mapper/root /mnt/var/cache/pacman/pkg
mount -o defaults,noatime,subvol=@log /dev/mapper/root /mnt/var/log
mount -o defaults,noatime /dev/nvme0n1p1 /mnt/boot/esp

# set up pacman mirrorlist

echo "Server = ${SETUP_MIRROR}" > /etc/pacman.d/mirrorlist

# install basic packages

pacstrap /mnt base base-devel

# create /etc/fstab

cat > /mnt/etc/fstab << EOF
PARTLABEL=esp    /boot/esp             vfat  defaults                      0 2
/dev/mapper/swap none                  swap  defaults                      0 0
/dev/mapper/root /                     btrfs defaults,noatime,subvol=@     0 0
/dev/mapper/root /home                 btrfs defaults,noatime,subvol=@home 0 0
/dev/mapper/root /var/log              btrfs defaults,noatime,subvol=@log  0 0
/dev/mapper/root /var/cache/pacman/pkg btrfs defaults,noatime,subvol=@pkg  0 0
EOF

# continue in chroot

cp setup-chroot.sh /mnt/root/setup-chroot.sh
arch-chroot /mnt /root/setup-chroot.sh
rm /mnt/root/setup-chroot.sh

# setup systemd-resolved DNS resolver

ln -sf /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf

# unmount chroot

umount -R {/mnt,/tmp/root}
cryptsetup close swap
cryptsetup close root
