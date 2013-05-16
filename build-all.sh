#!/bin/bash

IFS=$'\n'
for config in $(ls -1 config) ; do
	echo
	echo "==="
	echo "=== building config:"
	echo "=== $config"
	echo "==="
	echo
	echo
	
	"$(dirname "$0")/build.sh" "$@" "$config" || exit $?
done
