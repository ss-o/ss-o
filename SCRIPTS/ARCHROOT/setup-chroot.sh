#!/bin/bash

set -eux

SETUP_TIMEZONE=America/Los_Angeles
SETUP_LOCALE=en_US
SETUP_HOSTNAME=dev
SETUP_WIFI=wlp3s0
SETUP_USER=mmozeiko

# timezone

ln -sf /usr/share/zoneinfo/"${SETUP_TIMEZONE}" /etc/localtime
hwclock --systohc

# locale

echo "${SETUP_LOCALE}.UTF-8 UTF-8" > /etc/locale.gen
echo "LANG=${SETUP_LOCALE}.UTF-8" > /etc/locale.conf
locale-gen

# hostname

echo "${SETUP_HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${SETUP_HOSTNAME}.localdomain ${SETUP_HOSTNAME}
EOF

# install extra packages & remove unneeded ones

pacman -S --noconfirm vim iwd openssh git efitools sbsigntools intel-ucode btrfs-progs bash-completion pacman-contrib powertop
pacman -Rn --noconfirm dhcpcd netctl nano vi

# make console font larger

cat > /etc/vconsole.conf << EOF
FONT=latarcyrheb-sun32
EOF


# initramfs hook for opening encrypted swap

cat > /etc/initcpio/install/openswap << EOF
build ()
{
   add_runscript
}
help ()
{
  echo "Hook for opening encrypted swap partition"
}
EOF

cat > /etc/initcpio/hooks/openswap << EOF
run_hook ()
{
  mkdir openswap_keymount
  mount -o ro,subvol=/ /dev/mapper/root openswap_keymount
  cryptsetup open /dev/disk/by-partlabel/cryptswap swap --type plain --cipher aes-xts-plain64 --key-size 256 --key-file openswap_keymount/swap.key --allow-discards
  umount openswap_keymount
}
EOF

# initramfs configuration

sed -i 's/^\(MODULES=\).*$/\1(i915)/' /etc/mkinitcpio.conf
sed -i 's/^\(BINARIES=\).*$/\1("\/usr\/bin\/btrfs")/' /etc/mkinitcpio.conf
sed -i 's/^\(HOOKS=\).*$/\1(base udev autodetect keyboard consolefont modconf block encrypt openswap resume filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's/^#\(COMPRESSION="xz"\)$/\1/' /etc/mkinitcpio.conf

echo "options i915 fastboot=1 enable_fbc=1 enable_guc=3 enable_psr=0" > /etc/modprobe.d/i915.conf

# rebuild initramfs & remove fallback

sed -i 's/\(PRESETS=\).*$/\1("default")/' /etc/mkinitcpio.d/linux.preset
mkinitcpio -p linux
rm /boot/initramfs-linux-fallback.img

# install bootloader

bootctl --path=/boot/esp install

cat > /boot/esp/loader/loader.conf << EOF
default ArchLinux
timeout 0
EOF

cat > /boot/esp/loader/entries/ArchLinux.conf << EOF
title Arch Linux
efi   /ArchLinux.efi
EOF

# enable Secure Boot

mkdir /boot/keys
cd /boot/keys

openssl req -newkey rsa:4096 -nodes -keyout PK.key -new -x509 -sha256 -days 3650 -subj "/CN=MY PK/" -out PK.crt
openssl req -newkey rsa:4096 -nodes -keyout KEK.key -new -x509 -sha256 -days 3650 -subj "/CN=MY KEK/" -out KEK.crt
openssl req -newkey rsa:4096 -nodes -keyout db.key -new -x509 -sha256 -days 3650 -subj "/CN=MY DB/" -out db.crt

openssl x509 -outform DER -in PK.crt -out PK.cer
openssl x509 -outform DER -in KEK.crt -out KEK.cer
openssl x509 -outform DER -in db.crt -out db.cer

uuidgen --random > GUID.txt
cert-to-efi-sig-list -g "$(< GUID.txt)" PK.crt PK.esl
cert-to-efi-sig-list -g "$(< GUID.txt)" KEK.crt KEK.esl
cert-to-efi-sig-list -g "$(< GUID.txt)" db.crt db.esl

sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt PK PK.esl PK.auth
sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt PK /dev/null null_PK.auth
sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt KEK KEK.esl KEK.auth

efi-updatevar -e -f KEK.esl KEK
efi-updatevar -e -f db.esl db
efi-updatevar -f PK.auth PK

chmod 0400 /boot/keys/*
chmod 0500 /boot/keys

cat > /boot/cmdline.txt << EOF
rw quiet loglevel=3 udev.log_priority=3 nowatchdog \
cryptdevice=PARTLABEL=cryptroot:root:allow-discards \
resume=LABEL=swap \
root=LABEL=root rootflags=compress=zstd,subvol=@
EOF

cat > /boot/sign-bootloader.sh << EOF
#!/bin/bash

set -eu

/usr/bin/bootctl --path=/boot/esp update
sbsign --key /boot/keys/db.key --cert /boot/keys/db.crt --output /boot/esp/EFI/BOOT/BOOTX64.EFI /boot/esp/EFI/BOOT/BOOTX64.EFI
sbsign --key /boot/keys/db.key --cert /boot/keys/db.crt --output /boot/esp/EFI/systemd/systemd-bootx64.efi /boot/esp/EFI/systemd/systemd-bootx64.efi
EOF

cat > /boot/sign-kernel.sh << EOF
#!/bin/bash

set -eu

cat "/boot/intel-ucode.img" "/boot/initramfs-linux.img" > "/tmp/init.img"

objcopy \
  --add-section .osrel="/etc/os-release"                              --change-section-vma .osrel=0x20000    \
  --add-section .cmdline="/boot/cmdline.txt"                          --change-section-vma .cmdline=0x30000  \
  --add-section .splash="/usr/share/systemd/bootctl/splash-arch.bmp"  --change-section-vma .splash=0x40000   \
  --add-section .linux="/boot/vmlinuz-linux"                          --change-section-vma .linux=0x2000000  \
  --add-section .initrd="/tmp/init.img"                               --change-section-vma .initrd=0x3000000 \
  "/usr/lib/systemd/boot/efi/linuxx64.efi.stub" \
  "/boot/esp/ArchLinux.efi"

rm /tmp/init.img

sbsign --key /boot/keys/db.key --cert /boot/keys/db.crt --output /boot/esp/ArchLinux.efi /boot/esp/ArchLinux.efi
EOF

mkdir -p /etc/pacman.d/hooks

cat > /etc/pacman.d/hooks/999-sign-bootloader.hook << EOF
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = systemd

[Action]
Description = Signing bootloader
When = PostTransaction
Exec = /boot/sign-bootloader.sh
Depends = sbsigntools
EOF

cat > /etc/pacman.d/hooks/999-sign-kernel.hook << EOF
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux
Target = mkinitcpio
Target = mkinitcpio-busybox

[Action]
Description = Signing kernel
When = PostTransaction
Exec = /boot/sign-kernel.sh
Depends = sbsigntools
Depends = intel-ucode
EOF

chmod +x /boot/sign-{bootloader,kernel}.sh
/boot/sign-bootloader.sh
/boot/sign-kernel.sh

# keep only latest 3 versions of packages

cat > /etc/pacman.d/hooks/pacman-cleanup.hook << EOF
[Trigger]
Type = Package
Operation = Remove
Operation = Install
Operation = Upgrade
Target = *

[Action]
Description = Keep only latest 3 versions of packages
When = PostTransaction
Exec = /usr/bin/paccache -rk3
EOF

# create powertop service

cat > /etc/systemd/system/powertop.service << EOF
[Unit]
Description=Powertop tunings

[Service]
ExecStart=/usr/bin/powertop --auto-tune
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# enable system services

mkdir -p /etc/systemd/system/sysinit.target.wants
mkdir -p /etc/systemd/system/sockets.target.wants
mkdir -p /etc/systemd/system/network-online.target.wants
mkdir -p /etc/systemd/system/timers.target.wants

ln -s /dev/null /etc/systemd/system/lvm2-lvmetad.service
ln -s /dev/null /etc/systemd/system/lvm2-lvmetad.socket

ln -s /usr/lib/systemd/system/systemd-timesyncd.service /etc/systemd/system/dbus-org.freedesktop.timesync1.service
ln -s /usr/lib/systemd/system/systemd-timesyncd.service /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service

ln -s /usr/lib/systemd/system/systemd-networkd.service             /etc/systemd/system/dbus-org.freedesktop.network1.service
ln -s /usr/lib/systemd/system/systemd-networkd.service             /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -s /usr/lib/systemd/system/systemd-networkd.socket              /etc/systemd/system/sockets.target.wants/systemd-networkd.socket
ln -s /usr/lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service

ln -s /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/dbus-org.freedesktop.resolve1.service
ln -s /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service

ln -s /etc/systemd/system/powertop.service /etc/systemd/system/multi-user.target.wants/powertop.service

ln -s /usr/lib/systemd/system/iwd.service /etc/systemd/system/multi-user.target.wants/

ln -s /usr/lib/systemd/system/fstrim.timer /etc/systemd/system/timers.target.wants/fstrim.timer

# workaround for iwd/systemd bug: https://bbs.archlinux.org/viewtopic.php?pid=1818587#p1818587

mkdir -p /etc/systemd/system/iwd.service.d
cat > /etc/systemd/system/iwd.service.d/override.conf << EOF
[Unit]
BindsTo=sys-subsystem-net-devices-${SETUP_WIFI}.device
After=sys-subsystem-net-devices-${SETUP_WIFI}.device

[Service]
ExecStart=
ExecStart=/usr/lib/iwd/iwd --interface ${SETUP_WIFI}
EOF

# systemd-networkd config

cat > /etc/systemd/network/wifi.network << EOF
[Match]
Name=${SETUP_WIFI}

[Network]
DHCP=yes

[DHCP]
RouteMetric=20
EOF

# sysctl tweaks

cat > /etc/sysctl.d/tweaks.conf << EOF
# less swapping
vm.swappiness = 0
vm.dirty_ratio = 3
vm.dirty_background_ratio = 2

# no magic-sysrq key
kernel.sysrq = 0

# max connections
net.core.somaxconn = 1024

# network memory limits
net.core.rmem_default = 1048576
net.core.rmem_max = 16777216
net.core.wmem_default = 1048576
net.core.wmem_max = 16777216
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# set tcp keepalive to 120 sec
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF

# pacman & makepkg config

sed -i 's/^#\(Color\).*$/\1/'           /etc/pacman.conf
sed -i 's/^#\(TotalDownload\).*$/\1/'   /etc/pacman.conf
sed -i 's/^#\(VerbosePkgLists\).*$/\1/' /etc/pacman.conf

sed -i "s/^#\(MAKEFLAGS=\).*$/\1\"-j`nproc`\"/" /etc/makepkg.conf
sed -i 's/^\(PKGEXT=\).*$/\1".pkg.tar"/'        /etc/makepkg.conf

# sudo config

echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# set vim as default editor

echo "export EDITOR=vim" > /etc/profile.d/editor.sh

# non-root user

useradd -g users -G wheel -m -s /bin/bash "${SETUP_USER}"
passwd "${SETUP_USER}"

# disable root password

passwd -l root

# autologin user on boot

mkdir -p "/etc/systemd/system/getty@tty1.service.d"
cat > "/etc/systemd/system/getty@tty1.service.d/override.conf" << EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin ${SETUP_USER} --noclear %I \$TERM
Type=simple
EOF
