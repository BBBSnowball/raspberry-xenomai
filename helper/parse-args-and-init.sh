# Parse arguments and initialize some variables that we usually use.


# break immediately, if anything fails
set -e


### parse arguments ###

# save arguments (sometimes used to call other scripts)
ARGS=("$@")

# default values of arguments
CONFIGNAME=""
CLEAN_SOURCES=0
SHOW_USAGE=0
REBUILD=0
QUIET=0

# look at each argument and change the variables
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
		--quiet)
			QUIET=1
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
	show_additional_arguments	# provided by calling script
	echo "Valid configurations:" >&2
	ls -1 config | sed 's/^/  /' >&2
	exit 1
fi
CONFIG="config/$CONFIGNAME"


### common variables ###

# the directories we're going to use
# (May also be used by the config script.)
basedir="$(readlink -f .)"
linux_tree="$basedir/linux"
xenomai_root="$basedir/xenomai"
rpi_tools="$basedir/tools"
build_root="$basedir/build/$CONFIGNAME"
dependency_info_file="$build_root/dependency-info.txt"

# variables for the build
export PATH="$PATH:$rpi_tools/arm-bcm2708/arm-bcm2708-linux-gnueabi/bin"
export ARCH=arm
GNU_SYSTEM_TYPE=arm-bcm2708-linux-gnueabi
export CROSS_COMPILE="$GNU_SYSTEM_TYPE-"
XENOMAI_CFLAGS="-marm -march=armv6 -mtune=arm1136j-s"
XENOMAI_LDFLAGS="$XENOMAI_CFLAGS"


### helper functions ###

at_step() {
	echo
	echo "==== $1 ===="

	# set title, if we are running in screen
	if [ "$TERM" == screen ] ; then
		echo -ne '\033k'"$1"'\033\\'
	fi
}
