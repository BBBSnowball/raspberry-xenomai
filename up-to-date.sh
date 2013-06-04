#!/bin/bash

# go to root folder of our git
cd "$(dirname "$0")"

show_additional_arguments() {
	echo -n 	# we don't have additional arguments
}

source helper/parse-args-and-init.sh

if [ "$QUIET" -gt 0 ] ; then
	# 'kill' stdout
	exec >/dev/null
fi


# If the dependency-info file doesn't exist, we cannot be up-to-date.
if [ ! -f "$dependency_info_file" ] ; then
	echo "no dependency-info file (should be at $dependency_info_file)"
	exit 1
fi


# Have the dependencies changed?
#NOTE output of diff goes to stdout to tell the user about the changes
if ! diff -u0 "$dependency_info_file" --label "build/$CONFIGNAME/dependency-info.txt" <(./dependency-info.sh "${ARGS[@]}") --label "<current>" ; then
	echo "dependencies have changed ^^"
	exit 1
fi


# files that are created by the build
# (without intermediary files)
TARGET_FILES=("$build_root/linux-modules.tar.bz2" "$build_root/xenomai-for-pi.tar.bz2" "$build_root/kernel.img")

# run config script because it might add/change target files
CONFIG_DEPENDENCIES=yes
load_config


# Are all target files newer than the dependency-info file?
for target in "${TARGET_FILES[@]}" ; do
	if [ ! -e "$target" -o "$dependency_info_file" -nt "$target" ] ; then
		echo "'$target' is not up-to-date"
		exit 1
	fi
done


# We couldn't find any reason to rebuild it -> it is up-to-date
echo "up-to-date"
exit 0
