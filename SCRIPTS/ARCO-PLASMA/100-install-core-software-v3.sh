#!/bin/bash
set -e
##################################################################################################################
# Author 	: Erik Dubois
# Website : https://www.erikdubois.be
# Website	: https://www.arcolinux.info
# Website	:	./https://www.arcolinux.com
# Website	:	https://www.arcolinuxd.com
# Website	:	https://www.arcolinuxforum.com
##################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################

#software from Arch Linux repositories

#sudo pacman -S --noconfirm --needed autorandr
sudo pacman -S --noconfirm --needed flameshot
sudo pacman -S --noconfirm --needed discord
sudo pacman -S --noconfirm --needed gitfiend
#sudo pacman -S --noconfirm --needed dropbox
sudo pacman -S --noconfirm --needed spotify
sudo pacman -S --noconfirm --needed telegram-desktop
sudo pacman -S --noconfirm --needed insync

#just of these two for youtube
sudo pacman -S --noconfirm --needed vivaldi-ffmpeg-codecs
#for netflix
sudo pacman -S --noconfirm --needed vivaldi-widevine
sudo pacman -S --noconfirm --needed vivaldi
sudo pacman -S --noconfirm --needed chromium
sudo pacman -S --noconfirm --needed brave
sudo pacman -S --noconfirm --needed vlc

sudo pacman -S --noconfirm --needed wps-office
sudo pacman -S --noconfirm --needed ttf-wps-fonts
sudo pacman -S --noconfirm --needed wps-office-mime

sudo pacman -S --noconfirm --needed arcolinux-meta-fun

sudo pacman -S --noconfirm --needed simplescreenrecorder
sudo pacman -S --noconfirm --needed brave

###############################################################################################

echo "################################################################"
echo "################### core software installed"
echo "################################################################"
