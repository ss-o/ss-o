#!/bin/bash

#<UDF name="USERNAME" label="Username">

#<UDF name="USERPASSWORD" label="Password">

#<UDF name="USERPUBKEY" label="User SSH public key" default="">

#<UDF name="HOSTNAME" label="Hostname (FQDN)" default="">

# Last update: November 04th, 2018

# Author: Lincoln Lamas <falecom@interlli.ga>

set -e

if [ ! -z "$HOSTNAME" ]; then

  hostnamectl set-hostname $HOSTNAME

  echo "127.0.0.1   $HOSTNAME" >> /etc/hosts

fi

# Set up user account

adduser $USERNAME --disabled-password --gecos ""

echo "$USERNAME:$USERPASSWORD" | chpasswd

adduser $USERNAME sudo

# If user provided an SSH public key, whitelist it, disable SSH password authentication, and allow passwordless sudo

if [ ! -z "$USERPUBKEY" ]; then

  mkdir -p /home/$USERNAME/.ssh

  echo "$USERPUBKEY" >> /home/$USERNAME/.ssh/authorized_keys

  chown -R "$USERNAME":"$USERNAME" /home/$USERNAME/.ssh

  chmod 600 /home/$USERNAME/.ssh/authorized_keys

  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

  echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

fi

# Installing Docker and AzuraCast

mkdir -p /var/azuracast \

  && cd /var/azuracast \

  && curl -L https://raw.githubusercontent.com/AzuraCast/AzuraCast/master/docker.sh > docker.sh \

  && chmod a+x docker.sh \

  && yes | ./docker.sh install

# Disable root SSH access

sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config