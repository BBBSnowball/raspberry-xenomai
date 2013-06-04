#!/bin/bash

# This script prints information about all dependencies of a configuration.


# go to root folder of our git
cd "$(dirname "$0")"

show_additional_arguments() {
	echo -n 	# we don't have additional arguments
}

source helper/parse-args-and-init.sh


# file dependencies
DEP_FILES=();

# record version of build.sh
BUILD_SH_VERSION="$(sed -n 's/^\#\s*VERSION:\s*\([0-9]\+\.[0-9]\+\).*/\1/p' build.sh)"
echo "build.sh version: $BUILD_SH_VERSION"

# run config script
CONFIG_DEPENDENCIES=yes
load_config

# config can set special variables with additional dependencies
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
