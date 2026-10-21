#!/bin/zsh
# Run a VM headlessly under Apple's Virtualization framework, as UTM does with "Use Apple
# Virtualization", with Apple's Rosetta shared in for x86-64 programs. vzvm.swift is compiled
# and ad-hoc signed with the virtualization entitlement on first use, into work/vzvm/.
#
# usage: vzvm.sh NAME [--iso ISO] [--disk RAW_DISK] [--qga-port PORT] [--cpus N] [--memory GB] [--no-rosetta]
#   NAME keeps the VM's UEFI variables in work/vzvm/NAME. Disks must be raw images, not qcow2.
emulate -L zsh
setopt err_exit

NAME=${1:?usage: vzvm.sh NAME [--iso ISO] [--disk RAW_DISK] [--qga-port PORT] [--cpus N] [--memory GB] [--no-rosetta]}
shift
DIR=${0:A:h:h}/work/vzvm
BIN=$DIR/vzvm
mkdir -p $DIR/$NAME
if [[ ! -x $BIN || ${0:A:h}/vzvm.swift -nt $BIN ]]; then
  swiftc -O -o $BIN ${0:A:h}/vzvm.swift
  print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.virtualization</key><true/></dict></plist>' > $DIR/entitlements.plist
  codesign -s - -f --entitlements $DIR/entitlements.plist $BIN
fi
exec $BIN --vars $DIR/$NAME/efi-vars "$@"
