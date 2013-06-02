#!/bin/bash

# copy this script to the Pi and run it

#NOTE I tried it on a fresh install of Raspbian
#     (2013-02-09-wheezy-raspbian.zip). I only changed
#     a few things:
#     - expand root fs, change password, enable ssh, finish config dialog
#     - add my SSH key
#     - sudo aptitude update && sudo aptitude install byobu htop

CONFIG=linux-3.2.21-snowball
MIRROR=http://192.168.178.57:8000/jenkins/artifact/RaspberryPi-Xenomai/build
#MIRROR=http://jenkins.bbbsnowball.de:3000/jenkins/artifact/RaspberryPi-Xenomai/build
XENOMAI_VERSION=2.5.4

if [ -n "$1" ] ; then
	CONFIG="$1"
fi
if [ -n "$2" ] ; then
	XENOMAI_VERSION="$2"
fi
if [ -n "$3" ] ; then
	MIRROR="$3"
fi


# break on error
set -e


if [ "$(whoami)" != "root" ] ; then
	echo "You must run this script as root! (use sudo)"
	exit 1
fi

if [ ! -e "/boot/start.elf" ] ; then
	echo "The file /boot/start.elf doesn't exist, so this is"
	echo "either not a Raspberry Pi or you need to mount /boot."
	echo "Please mount /boot and try again."
	exit 1
fi


BUILD_ROOT="$MIRROR/$CONFIG"
XENOMAI_DEBS=( \
		libxenomai1_${XENOMAI_VERSION}_arm.deb \
		libxenomai-dev_${XENOMAI_VERSION}_arm.deb \
		xenomai-doc_${XENOMAI_VERSION}_all.deb \
		xenomai-runtime_${XENOMAI_VERSION}_arm.deb)

for file in linux-modules.tar.bz2 kernel.img \
 		${XENOMAI_DEBS[@]/#/xenomai/deb/}
do
	wget "$BUILD_ROOT/$file"
done

# unpack modules
echo "Unpacking kernel modules..."
tar -C / -xjf linux-modules.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner

# replace kernel
echo "Replacing kernel..."
cp /boot/kernel.img kernel.img.old
cp kernel.img /boot/kernel.img

# install xenomai debs
echo "Installing Xenomai..."
for deb in "${XENOMAI_DEBS[@]}" ; do
	dpkg -i "$deb"
done
