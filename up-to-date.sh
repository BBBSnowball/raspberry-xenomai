#!/bin/bash


# go to root folder of our git
cd "$(dirname "$0")"

# read arguments
ARGS=("$@")
CONFIGNAME=""
CLEAN_SOURCES=0
SHOW_USAGE=0
while test "$#" -gt 0 ; do
	case "$1" in
		-h|--help)
			SHOW_USAGE=1
			;;
		--clean-sources|--rebuild)
			# You may pass the same arguments as for
			# build.sh, but we ignore them.
			;;
		--quiet)
			# 'kill' stdout
			exec >/dev/null
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

# first argument should be the configuration
if [ "$SHOW_USAGE" -gt 0 -o -z "$CONFIGNAME" -o ! -d "config/$1" ] ; then
	echo "This script prints information about all dependencies of a configuration."
	echo "Usage: $0 configuration-name" >&2
	echo "Valid configurations:" >&2
	ls -1 config | sed 's/^/  /' >&2
	exit 1
fi
CONFIG="config/$CONFIGNAME"


# the directories we're going to use
# (May be used by the config script.)
basedir="$(readlink -f .)"
linux_tree="$basedir/linux"
xenomai_root="$basedir/xenomai"
rpi_tools="$basedir/tools"
build_root="$basedir/build/$CONFIGNAME"


# If the dependency-info file doesn't exist, we cannot be up-to-date.
if [ ! -f "$build_root/dependency-info.txt" ] ; then
	echo "no dependency-info file (should be at $build_root/dependency-info.txt)"
	exit 1
fi


# Have the dependencies changed?
#NOTE output of diff goes to stdout to tell the user about the changes
if ! diff -u0 "$build_root/dependency-info.txt" --label "build/$CONFIGNAME/dependency-info.txt" <(./dependency-info.sh "${ARGS[@]}") --label "<current>" ; then
	echo "dependencies have changed ^^"
	exit 1
fi


# files that are created by the build
# (without intermediary files)
TARGET_FILES=("$build_root/linux-modules.tar.bz2" "$build_root/xenomai-for-pi.tar.bz2" "$build_root/kernel.img")

# run config script because it might add/change target files
CONFIG_DEPENDENCIES=yes
source "$CONFIG/config"


# Are all target files newer than the dependency-info file?
for target in "${TARGET_FILES[@]}" ; do
	if [ ! -e "$target" -o "$build_root/dependency-info.txt" -nt "$target" ] ; then
		echo "'$target' is not up-to-date"
		exit 1
	fi
done


# We couldn't find any reason to rebuild it -> it is up-to-date
echo "up-to-date"
exit 0
