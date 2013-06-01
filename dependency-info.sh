#!/bin/bash

# This script prints information about all dependencies of a configuration.

# break immediately, if anything fails
set -e

# file dependencies
DEP_FILES=();

BUILD_SH_VERSION="$(sed -n 's/^\#\s*VERSION:\s*\([0-9]\+\.[0-9]\+\).*/\1/p' build.sh)"
echo "build.sh version: $BUILD_SH_VERSION"

# go to root folder of our git
cd "$(dirname "$0")"

# read arguments
CONFIGNAME=""
CLEAN_SOURCES=0
SHOW_USAGE=0
while test "$#" -gt 0 ; do
	case "$1" in
		-h|--help)
			SHOW_USAGE=1
			;;
		--clean-sources|--rebuild|--quiet)
			# You may pass the same arguments as for
			# build.sh, but we ignore them.
			;;
		*)
			if [ -n "$CONFIGNAME" ] ; then
				echo "We already have a config." >&2
				SHOW_USAGE=1
			fi
			CONFIGNAME="$1"
			;;
	esac
	shift
done

# first argument should be the configuration to build
if [ "$SHOW_USAGE" -gt 0 -o -z "$CONFIGNAME" -o ! -d "config/$1" ] ; then
	echo "This script prints information about all dependencies of a configuration."
	echo "Usage: $0 configuration-name" >&2
	echo "Valid configurations:" >&2
	ls -1 config | sed 's/^/  /' >&2
	exit 1
fi
CONFIG="config/$CONFIGNAME"

# the directories we're going to use
basedir="$(readlink -f .)"
linux_tree="$basedir/linux"
xenomai_root="$basedir/xenomai"
rpi_tools="$basedir/tools"
build_root="$basedir/build/$CONFIGNAME"

# run config script
CONFIG_DEPENDENCIES=yes
source "$CONFIG/config"
DEP_FILES=("${DEP_FILES[@]}" "$CONFIG/config")
if [ -n "$DEPENDENCY_INFO" ] ; then
	echo "$DEPENDENCY_INFO"
fi
if [ -n "$DEPENDENCIES" ] ; then
	DEP_FILES=("${DEP_FILES[@]}" "${DEPENDENCIES[@]}")
fi

# checkout right version in submodules and print hash
# (We cannot use the tags themselves because their meaning might change.)
#NOTE We don't add the versions file as a dependency, as 
if [ -e "$CONFIG/versions" ] ; then
	while read name version ; do
		# ignore comments and empty lines
		if [[ $name != "" ]] && [[ $name != \#* ]] ; then
			# get hash for the tag/branch/...
			hash="$(cd "$name" ; git log -1 --format=format:%H "$version")"
			echo "git $name: $hash"
		fi
	done < "$CONFIG/versions"

	# read ignores the last line, if it doesn't end with a
	# newline, so we fail in that case
	if [ -n "$name" -o -n "$version" ] ; then
		echo "ERROR: config file $CONFIG/versions doesn't have a trailing newline!" >&2
		exit 1
	fi
fi

#NOTE: those variables are empty, if the config script doesn't set them
#      -> empty means "default value"
echo "ARCH=$ARCH"
echo "CROSS_COMPILE=$CROSS_COMPILE"

DEP_FILES=("${DEP_FILES[@]}" "$ADEOS_PATCH" "$KERNEL_CONFIG")

# add patches
if [ -e "$CONFIG/patches" ] ; then
	DEP_FILES=("${DEP_FILES[@]}" "$CONFIG/patches")
	while read dir patch ; do
		# ignore comments and empty lines
		if [[ $dir != "" ]] && [[ $dir != \#* ]] ; then
			echo "patch for $dir: $CONFIG/$patch"
			DEP_FILES=("${DEP_FILES[@]}" "$CONFIG/$patch")
		fi
	done < "$CONFIG/patches"

	# read ignores the last line, if it doesn't end with a
	# newline, so we fail in that case
	if [ -n "$dir" -o -n "$patch" ] ; then
		echo "ERROR: config file $CONFIG/patches doesn't have a trailing newline!" >&2
		exit 1
	fi
fi

# clean paths of file dependencies
DEP_FILES2=()
for file in "${DEP_FILES[@]}" ; do
	# make absolute path
	absfile="$(readlink -f "$file")"

	# is it in basedir?
	# (If it is not, we copy it verbatim.)
	if [[ "$absfile" == "$basedir"* ]] ; then
		# cut basedir part
		file="${absfile:${#basedir}}"

		# remove leading slash
		if [[ "$file" == /* ]] ; then
			file="${file:1}"
		fi
	fi

	DEP_FILES2=("${DEP_FILES2[@]}" "$file")
done

# print md5 hash of dependent files
#TODO sort and make unique
md5sum "${DEP_FILES2[@]}"
