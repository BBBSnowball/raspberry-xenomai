#!/bin/bash

# VERSION: 1.0.0 (major.minor.patch)
# Change major or minor version, if the build result may
# change because of your edits to this script. All configurations
# will be rebuilt. A change to the 3rd number won't cause a
# rebuild.

# This script is based on this guide:
# http://diy.powet.eu/2012/07/25/raspberry-pi-xenomai/
# If the script doesn't work, you may want to use the guide. I have
# used the guide and it does work, so any bugs are my fault.

#NOTE The submodules shouldn't have any changes. Any changes will be
#     deleted during the build!!!

#NOTE The script should work, if its absolute path contains 'special'
#     characters (e.g. a space). However, I never test that, so you
#     might want to use a path without any spaces.

#NOTE You have to install some libraries. On a Debian/Ubuntu you can do this:
#     sudo aptitude install lib32z1 libncurses5-dev
#     
#     lib32z1:         for build tools on x64 host
#     libncurses5-dev: only for 'make menuconfig'

#NOTE All config files snould have a trailing newline! If you use vi
#     or nano, they will automatically do the right thing.
#     http://dbaspot.com/shell/381104-howto-read-file-line-line-bash.html

# The kernel should be used with Rasbian:
# download Raspbian from http://www.raspberrypi.org/downloads

# interesting links:
# http://diy.powet.eu/2012/07/25/raspberry-pi-xenomai/
# http://www.xenomai.org/documentation/xenomai-2.6/html/README.INSTALL/
# http://linuxcnc.mah.priv.at/rpi/rpi-rtperf.html

# break immediately, if anything fails
set -e

# go to root folder of our git
cd "$(dirname "$0")"

# read arguments
ARGS=("$@")
CONFIGNAME=""
CLEAN_SOURCES=0
SHOW_USAGE=0
REBUILD=0
while test "$#" -gt 0 ; do
	case "$1" in
		-h|--help)
			SHOW_USAGE=1
			;;
		--clean-sources)
			CLEAN_SOURCES=1
			;;
		--rebuild)
			REBUILD=1
			;;
		*)
			if [ -n "$CONFIGNAME" ] ; then
				echo "We already have a config ($CONFIGNAME)." >&2
				SHOW_USAGE=1
			fi
			CONFIGNAME="$1"
			;;
	esac
	shift
done

# first argument should be the configuration to build
if [ "$SHOW_USAGE" -gt 0 -o -z "$CONFIGNAME" -o ! -d "config/$1" ] ; then
	echo "Usage: $0 configuration-name" >&2
	echo "  --clean-sources  Kill changes and unversioned files in submodules"
	echo "  --rebuild        Rebuild, even if it seems to be up-to-date"
	echo "Valid configurations:" >&2
	ls -1 config | sed 's/^/  /' >&2
	exit 1
fi
CONFIG="config/$CONFIGNAME"

# exit early, if build is up-to-date
if [ "$REBUILD" -le "0" ] && ./up-to-date.sh --quiet "${ARGS[@]}" ; then
	echo "already up-to-date"
	exit 0
fi

if [ "$CLEAN_SOURCES" -le 0 ] ; then
	echo "=========================================" >&2
	echo "The build will fail, if you run it a"      >&2
	echo "second time because we're not cleaning"    >&2
	echo "the source folders. You may want to use"   >&2
	echo "the option --clean-sources to do so. This" >&2
	echo "will remove all changes and unversioned"   >&2
	echo "files in the submodules, so use it with"   >&2
	echo "care!"                                     >&2
	echo "=========================================" >&2
fi

at_step() {
	echo
	echo "==== $1 ===="

	# set title, if we are running in screen
	[ "$TERM" == screen ] && echo -ne '\033k'"$1"'\033\\'
}

# we may have to fetch the submodules
at_step "fetch dependencies"
#if [ ! -d "linux" -o ! -d "tools" -o ! -d "xenomai" ] ; then
	git submodule init
	git submodule update
#fi

# checkout right version of kernel and xenomai and kill
# any changes and unversioned files
#NOTE Yes, this is dangerous, but we need that for an
#     unattended build.
#TODO Add a very scary note to all the places that a user
#     will read before running the script.
if [ "$CLEAN_SOURCES" -gt 0 -a -e "$CONFIG/versions" ] ; then
	at_step "clean sources"
	#NOTE This cleans only those repos that have a version
	#     requirement in the config file.
	while read name version ; do
		# ignore comments and empty lines
		if [[ $name != "" ]] && [[ $name != \#* ]] ; then
			echo "clean $name and checkout $version..."
			# reset any changed
			( cd "$name" && git reset --hard HEAD )
			# delete unversioned files
			( cd "$name" && git clean -f -d -x )
			# get the version we want
			( cd "$name" && git checkout "$version" )
		fi
	done < "$CONFIG/versions"

	# read ignores the last line, if it doesn't end with a
	# newline, so we fail in that case
	if [ -n "$name" -o -n "$version" ] ; then
		echo "ERROR: config file $CONFIG/versions doesn't have a trailing newline!" >&2
		exit 1
	fi
fi

# the directories we're going to use
basedir="$(readlink -f .)"
linux_tree="$basedir/linux"
xenomai_root="$basedir/xenomai"
rpi_tools="$basedir/tools"
build_root="$basedir/build/$CONFIGNAME"

# variables for the build
export PATH="$PATH:$rpi_tools/arm-bcm2708/arm-bcm2708-linux-gnueabi/bin"
export ARCH=arm
export CROSS_COMPILE=arm-bcm2708-linux-gnueabi-

# config script may change the variables and it has to
# set some additional variables:
# ADEOS_PATCH="$xenomai_root/ksrc/arch/arm/patches/ipipe-core-3.2.21-arm-1.patch"
# KERNEL_CONFIG=...
source "$CONFIG/config"

# can we access the compiler?
at_step "test compiler"
if ! arm-bcm2708-linux-gnueabi-gcc --version ; then
	if which arm-bcm2708-linux-gnueabi-gcc >/dev/null ; then
		echo "ARM compiler exists and is in PATH, but we cannot run it." >&2
		echo "You may have to install TODO." >&2
		exit 1
	else
		echo "Couldn't find ARM compiler, but it should be in the tools git. This is weird. Sorry." >&2
		exit 1
	fi
fi


# clean kernel before applying the patches
at_step "clean linux tree"
make -C "$linux_tree" mrproper

# apply Xenomai patch to kernel
at_step "prepare linux tree for xenomai"
"$xenomai_root/scripts/prepare-kernel.sh" --arch="$ARCH" --adeos="$ADEOS_PATCH" --linux="$linux_tree"

# apply our patches
at_step "apply patches"
if [ -e "$CONFIG/patches" ] ; then
	while read dir patch ; do
		# ignore comments and empty lines
		if [[ $dir != "" ]] && [[ $dir != \#* ]] ; then
			echo "$dir: $CONFIG/$patch"
			patch -f -p1 -d "$dir" < "$CONFIG/$patch"
		fi
	done < "$CONFIG/patches"

	# read ignores the last line, if it doesn't end with a
	# newline, so we fail in that case
	if [ -n "$dir" -o -n "$patch" ] ; then
		echo "ERROR: config file $CONFIG/patches doesn't have a trailing newline!" >&2
		exit 1
	fi
fi

# clean build directories
at_step "clean build directories"
rm -rf "$build_root"
mkdir -p "$build_root/"{linux,linux-modules,xenomai,xenomai-staging}

# save dependency information
./dependency-info.sh "${ARGS[@]}" >"$build_root/dependency-info.txt" \
	|| rm -rf "$build_root/dependency-info.txt"

# copy kernel config to build directory
cp "$KERNEL_CONFIG" "$build_root/linux/.config"

# If the config is for an older kernel, we have to update it. Usually we would use
# 'make oldconfig', which asks the user about new options. This script may run
# unattended, so we cannot ask for user input. Therefore, we use 'make oldnoconfig'
# which assumes 'no' for all questions.
#TODO I'd rather have an option that assumes the default answer...
#( cd linux ; make oldnoconfig "O=$build_root/linux" )
#TODO I couldn't convince oldnoconfig to use the provided config file instead of
#     my current config on the host.

# if you want to change some options
#sudo aptitude install libncurses5-dev
#make menuconfig ARCH=arm

# build tools need some 32-bit libraries
#aptitude install lib32z1

# kernel will be in $build_root/linux/arch/arm/boot/Image -> copy to rpi:/boot/kernel.img
#TODO use hardfloat?
at_step "build kernel"
make -C linux "ARCH=$ARCH" "CROSS_COMPILE=$CROSS_COMPILE" "O=$build_root/linux"
cp "$build_root/linux/arch/arm/boot/Image" "$build_root/kernel.img"
at_step "pack kernel modules"
make -C linux modules_install "ARCH=$ARCH" "CROSS_COMPILE=$CROSS_COMPILE" "O=$build_root/linux" INSTALL_MOD_PATH="$build_root/linux-modules"
# -> copy lib/modules/* to rpi:/lib/modules [only files and kernel dir, without source and build]
##tar -C "$build_root/linux-modules" -cjf "$build_root/linux-modules.tar.bz2" lib/firmware/ lib/modules/*/modules.* lib/modules/*/kernel
tar -C "$build_root/linux-modules" -cjf "$build_root/linux-modules.tar.bz2" --exclude=source --exclude=build lib
#scp "$build_root/linux-modules.tar.bz2" rpi:
#ssh root@rpi tar -C / -xjf ~/linux-modules.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner

# build xenomai
at_step "build xenomai"

mkdir -p "$build_root/xenomai"
# manual suggests that we add -march=armv4t to CFLAGS and LDFLAGS - I don't know
# the correct value for RPi, so I use the ones that the kernel uses (determined
# by 'ps -ef' *g*)
#TODO The resulting binaries don't work. I suspect this is because of a wrong
#     library path. I 'fixed' that by doing the build on the raspberry. However,
#     I need to find a way to cross-compile it.
( cd $build_root/xenomai && \
	$xenomai_root/configure \
		CFLAGS="-marm -march=armv6 -mtune=arm1136j-s" \
		LDFLAGS="-marm -march=armv6 -mtune=arm1136j-s" \
    	--build=i686-pc-linux-gnu --host=arm-bcm2708-linux-gnueabi )
make -C "$build_root/xenomai" DESTDIR="$build_root/xenomai-staging"
# Use install-data-am instead of install to avoid creating the devices which
# will fail, if we're not root. You have to do something like 'make devices'
# on the Raspberry to create them.
at_step "pack xenomai"
make -C "$build_root/xenomai" DESTDIR="$build_root/xenomai-staging" install-user
tar -C "$build_root/xenomai-staging" -cjf "$build_root/xenomai-for-pi.tar.bz2" .
#scp "$build_root/xenomai-for-pi.tar.bz2" rpi:
#ssh root@rpi tar -C / -xjf ~/xenomai-for-pi.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner


# quick hack
#cp -r /usr/xenomai/* /usr
#ldconfig
#=> doesn't work anyway :-(
#=> building on RPi			<=============================== !!!!!!!!

# This message is printed by the Xenomai 'make install'. I think this is
# the reason that the files don't work on the Raspberry (if compiled on
# the host).
## ----------------------------------------------------------------------
## Libraries have been installed in:
##    /usr/xenomai/lib
## 
## If you ever happen to want to link against installed libraries
## in a given directory, LIBDIR, you must either use libtool, and
## specify the full pathname of the library, or use the `-LLIBDIR'
## flag during linking and do at least one of the following:
##    - add LIBDIR to the `LD_LIBRARY_PATH' environment variable
##      during execution
##    - add LIBDIR to the `LD_RUN_PATH' environment variable
##      during linking
##    - use the `-Wl,-rpath -Wl,LIBDIR' linker flag
##    - have your system administrator add LIBDIR to `/etc/ld.so.conf'
## 
## See any operating system documentation about shared libraries for
## more information, such as the ld(1) and ld.so(8) manual pages.
## ----------------------------------------------------------------------
