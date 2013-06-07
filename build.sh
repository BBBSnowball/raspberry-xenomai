#!/bin/bash

# VERSION: 1.1.0 (major.minor.patch)
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
#     sudo aptitude install lib32z1 libncurses5-dev \
#                           git-buildpackage devscripts debhelper dh-kpatches findutils \
#                           kernel-package
#     (you may want to add --without-recommends)
#     lib32z1:          for build tools on x64 host
#     libncurses5-dev:  only for 'make menuconfig'
#     git-buildpackage: build deb package for Xenomai
#     kernel-package:   build deb package for kernel

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

# used by parse-args-and-init.sh
show_additional_arguments() {
	echo "  --clean-sources  Kill changes and unversioned files in submodules"
	echo "  --rebuild        Rebuild, even if it seems to be up-to-date"
}

source helper/parse-args-and-init.sh

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

# we may have to fetch the submodules
at_step "fetch dependencies"
git submodule sync
if [ "$CLEAN_SOURCES" -gt 0 ] ; then
	# we are allowed to throw away changes, so we can tell git to continue no matter what
	git submodule update --init --force
else
	# this will probably fail because git will rather fail than overwrite changed files
	git submodule update --init
fi

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

# config script may change the variables and it has to
# set some additional variables:
# ADEOS_PATCH="$xenomai_root/ksrc/arch/arm/patches/ipipe-core-3.2.21-arm-1.patch"
# KERNEL_CONFIG=...
at_step "load config"
load_config

# can we access the compiler?
at_step "test compiler"
if ! "$CROSS_COMPILE"gcc --version ; then
	if which "$CROSS_COMPILE"gcc >/dev/null ; then
		echo "ARM compiler exists and is in PATH, but we cannot run it." >&2
		echo "You may have to install some library (try lib32z1)." >&2
		if which ldd >/dev/null ; then
			echo >&2
			ldd "$(which "$CROSS_COMPILE"gcc)" >&2
		fi
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
"$xenomai_root/scripts/prepare-kernel.sh" --arch="$KERNEL_ARCH" --adeos="$ADEOS_PATCH" --linux="$linux_tree"

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
./dependency-info.sh "${ARGS[@]}" >"$dependency_info_file" \
	|| rm -rf "$dependency_info_file"

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

# choose build method (only tar is working!)
case tar in
	kernel-package)
		# THIS DOESN'T WORK, YET!
		# I couldn't get kernel-package to build it. Problems:
		# - It is confused by the -ipipe in the config and aborts.
		# - I cannot set the system type without dirty tricks.

		# http://elinux.org/RPi_Kernel_Compilation#Perform_the_compilation
		# http://debiananwenderhandbuch.de/kernelbauen.html

		at_step "build kernel (deb)"
		#TODO --revision
		#TODO kernel config
		#TODO make-kpkg doesn't pass -t to dpkg-architecture, so we have
		#     to pass it via a trick: set 'ha' in env and don't use --arch,
		#     so makefile doesn't overwrite 'ha'. This is very brittle and
		#     is likely to break on anything but wheezy.
		( cd "$linux_tree" && \
			ha="-a$ARCH -t$GNU_SYSTEM_TYPE" \
			make-kpkg --rootcmd fakeroot --append-to-version="-xenomai" \
			--cross-compile="$CROSS_COMPILE" \
			--us --uc \
			buildpackage)

		#TODO further steps are missing because I couldn't get the above to work correctly

		;;

	tar)
		# kernel will be in $build_root/linux/arch/arm/boot/Image -> copy to rpi:/boot/kernel.img
		#TODO use hardfloat?
		at_step "build kernel"
		make -C "$linux_tree" "ARCH=$KERNEL_ARCH" "CROSS_COMPILE=$CROSS_COMPILE" "O=$build_root/linux"
		cp "$build_root/linux/arch/$KERNEL_ARCH/boot/Image" "$build_root/kernel.img"
		at_step "pack kernel modules"
		make -C "$linux_tree" modules_install "ARCH=$KERNEL_ARCH" "CROSS_COMPILE=$CROSS_COMPILE" "O=$build_root/linux" INSTALL_MOD_PATH="$build_root/linux-modules"
		# -> copy lib/modules/* to rpi:/lib/modules [only files and kernel dir, without source and build]
		##tar -C "$build_root/linux-modules" -cjf "$build_root/linux-modules.tar.bz2" lib/firmware/ lib/modules/*/modules.* lib/modules/*/kernel
		tar -C "$build_root/linux-modules" -cjf "$build_root/linux-modules.tar.bz2" --exclude=source --exclude=build lib
		#scp "$build_root/linux-modules.tar.bz2" rpi:
		#ssh root@rpi tar -C / -xjf ~/linux-modules.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner

		#NOTE We assume that firmware is already present.

		#TODO build a fake deb package

		;;

	*)
		echo "invalid build method for kernel..."
		exit 1
		;;
esac

# build xenomai
at_step "build xenomai"

mkdir -p "$build_root/xenomai"
# manual suggests that we add -march=armv4t to CFLAGS and LDFLAGS - I don't know
# the correct value for RPi, so I use the ones that the kernel uses (determined
# by 'ps -ef' *g*)
#TODO The resulting binaries don't work. I suspect this is because of a wrong
#     library path. I 'fixed' that by doing the build on the raspberry. However,
#     I need to find a way to cross-compile it.

# Debian stuff in Xenomai repo is broken. We can either use the repo that is
# maintained by Debian (TODO where is it?) or quick-fix it.
# http://www.mail-archive.com/xenomai@xenomai.org/msg00462.html
#TODO make dh_shlibdeps work with cross-compilation (instead of disabling it)
#TODO Why does it want a newer version of findutils on wheezy?
#     (4.4.2 is >=4.2.28, at least I think so *g*)
( cd xenomai && patch -p0 -N <<EOF || true
--- debian/xenomai-runtime.install  2013-06-01 22:59:30.037755253 +0200
+++ debian/xenomai-runtime.install  2013-06-01 22:59:40.313755043 +0200
@@ -4 +3,0 @@
-usr/share/xenomai

--- debian/rules  2013-06-02 00:09:13.833669395 +0200
+++ debian/rules  2013-06-02 00:09:40.993668837 +0200@@ -120 +120 @@
-	dh_shlibdeps -i
+	#dh_shlibdeps -i
@@ -128 +128 @@
-	dh_builddeb -i
+	dh_builddeb --destdir="\$(DEB_DESTDIR)" -i
@@ -144 +144 @@
-	dh_shlibdeps -s
+	#dh_shlibdeps -s
@@ -154 +154 @@
-	dh_builddeb -s
+	dh_builddeb --destdir="\$(DEB_DESTDIR)" -s

--- debian.orig/control	2013-06-02 01:05:42.269599860 +0200
+++ debian/control	2013-06-02 01:05:55.237599594 +0200
@@ -5 +5 @@
-Build-Depends: debhelper (>= 7), dh-kpatches, findutils (>= 4.2.28)
+Build-Depends: debhelper (>= 7), dh-kpatches
EOF
)

# building according to this guide: http://www.xenomai.org/index.php/Building_Debian_packages

TEMP_BRANCH="build-temp-rpi"
MY_NAME="Benjamin Koch"
MY_EMAIL="bbbsnowball@gmail.com"

case debuild in
	git-buildpackage)
		# delete temporary branch, if it already exists
		( cd xenomai && git branch -D "$TEMP_BRANCH" || true )

		# create temporary branch and adjust changelog
		( cd xenomai && git checkout -b "$TEMP_BRANCH" HEAD )
		( cd xenomai && DEBEMAIL="$MY_EMAIL" DEBFULLNAME="$MY_NAME" debchange "build for Raspberry Pi" )
		( cd xenomai && git commit -a --author="$MY_NAME <$MY_EMAIL>" -m "build for Raspberry Pi" )

		# build it
		( cd xenomai && git-buildpackage \
							--git-debian-branch="$TEMP_BRANCH" \
							--git-export-dir="$build_root/xenomai-deb" \
							--git-dist=raspbian \
							--git-arch=armv6
							-uc -us )

		# delete the temporary branch
		( cd xenomai && git checkout HEAD^1 && git branch -D "$TEMP_BRANCH" )

		;;

	debuild)
		( cd xenomai && DEBEMAIL="$MY_EMAIL" DEBFULLNAME="$MY_NAME" debchange "build for Raspberry Pi" )
		#TODO ARCH and so on - does it work like this?
		# see `man dpkg-buildpackage` for info about options
		#NOTE dpkg-buildpackage options must be after other options
		#TODO pass CFLAGS and such via dpkg-buildflags
		#NOTE DEB_DESTDIR must 

		#TODO I couldn't get debuild to pass the -t option to dpkg-buildpackage
		#( cd xenomai && \
		#	-tarm-bcm2708-linux-gnueabi
		#	debuild \
		#	--set-envvar=ARCH="$ARCH" \
		#	--set-envvar=CROSS_COMPILE="$CROSS_COMPILE" \
		#	--set-envvar=DEB_CFLAGS_APPEND="-marm -march=armv6 -mtune=arm1136j-s" \
		#	--set-envvar=DEB_LDFLAGS_APPEND="-marm -march=armv6 -mtune=arm1136j-s" \
		#	-uc -us -a"$ARCH" -t"$GNU_SYSTEM_TYPE"
		#	 )

		#TODO We should let dpkg-buildpackage put the files into the build
		#     directory. Unfortunately, this breaks stuff.
		#DEB_DESTDIR="$build_root/xenomai/"
		DEB_DESTDIR=..

		( cd xenomai && \
			DEB_CFLAGS_APPEND="$XENOMAI_CFLAGS" \
			DEB_LDFLAGS_APPEND="$XENOMAI_LDFLAGS" \
			CFLAGS="$XENOMAI_CFLAGS" \
			LDFLAGS="$XENOMAI_LDFLAGS" \
			DEB_DESTDIR="$DEB_DESTDIR" \
			dpkg-buildpackage -a"$ARCH" -t"$GNU_SYSTEM_TYPE" \
				--changes-option="-u$DEB_DESTDIR"
		)

		mkdir -p "$build_root/xenomai/deb"
		mv *.deb xenomai_*.changes xenomai_*.dsc xenomai_*.tar.gz "$build_root/xenomai/deb"

		if [ "$ARCH" != "$FIX_DEB_ARCH" ] ; then
			# we have to compile for arm because dpkg tools don't work for ARCH=armhf
			# -> fix ARCH after building debs

			at_step "fix ARCH of xenomai debs"

			set_arch() {
				DEB_FILE="$1"
				WANTED_ARCH="$2"

				# we need a temporary directory
				T="$(tempfile)"
				rm "$T"
				mkdir "$T"

				# extract files and control files
				dpkg-deb -R "$DEB_FILE" "$T"

				# fix ARCH
				#TODO any other places?
				sed -ie 's/^Architecture: .*$/Architecture: '"$WANTED_ARCH"'/' "$T/DEBIAN/control"

				echo
				echo "DEBUG: looking for 'arm' in $DEB_FILE/DEBIAN after fixing"
				grep -r "arm" "$T/DEBIAN"
				echo "END DEBUG"
				echo

				# pack modified files
				#NOTE The file gets a different name now because ARCH has changed.
				DEB_FILE_FIXED="$(echo "$DEB_FILE" | sed -ne 's/_[a-z0-9A-Z]*\?\.deb$/_'"$WANTED_ARCH"'.deb/p')"
				if [ -z "$DEB_FILE_FIXED" ] ; then
					echo "ERROR: Couldn't determine name of fixed deb file" >&2
					exit 1
				fi
				#TODO If we parse a directory as the second argument, dpkg-deb will determine the name.
				dpkg-deb -b "$T" "$DEB_FILE_FIXED"

				# remove temporary directory
				rm -rf "$T"

				# remove deb with wrong ARCH
				if [ "$DEB_FILE" != "$DEB_FILE_FIXED" ] ; then
					rm "$DEB_FILE"
				fi
			}

			for deb in "$build_root/xenomai/deb/"*"_$ARCH.deb" ; do
				set_arch "$deb" "$FIX_DEB_ARCH"
			done

		fi

		;;

	tar)
		#NOTE This does NOT produce working libraries!

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


		#TODO this assumes a x64 build system...

		( cd $build_root/xenomai && \
			$xenomai_root/configure \
				CFLAGS="$XENOMAI_CFLAGS" \
				LDFLAGS="$XENOMAI_LDFLAGS" \
		    	--build=i686-pc-linux-gnu --host="$GNU_SYSTEM_TYPE" )
		make -C "$build_root/xenomai" DESTDIR="$build_root/xenomai-staging"
		# Use install-data-am instead of install to avoid creating the devices which
		# will fail, if we're not root. You have to do something like 'make devices'
		# on the Raspberry to create them.
		at_step "pack xenomai"
		make -C "$build_root/xenomai" DESTDIR="$build_root/xenomai-staging" install-user
		tar -C "$build_root/xenomai-staging" -cjf "$build_root/xenomai-for-pi.tar.bz2" .
		#scp "$build_root/xenomai-for-pi.tar.bz2" rpi:
		#ssh root@rpi tar -C / -xjf ~/xenomai-for-pi.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner

		;;

	*)
		echo "invalid build method for Xenomai..."
		exit 1
		;;
esac

# copy README file to build dir, so we can save it as a build artifact
if [ -f "$CONFIG/README" ] ; then
	cp "$CONFIG/README" "$build_root/"
fi

# calculate MD5 checksum of the files (useful for installer)
( cd "$build_root" && md5sum kernel.img linux-modules.tar.bz2 xenomai/deb/* >md5sums )
