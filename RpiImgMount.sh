#!/bin/sh

usage() {
  exec >&2
  printf "Usage : $(basename "${0}") [options] image.img mountpoint\n"
  printf "Usage : $(basename "${0}") [options] -u mountpoint\n"
  printf "  Mount/Umount raw RaspberryPi OS image (assumes boot partition\n"
  printf "  is the first one, and root partition the second one)\n"
  printf "options :\n"
  printf "  -h : display this help message\n"
  exit 1
}

error()   { printf "Error : ${1}\n" >&2; exit ${2}; }
warning() { printf "Warning : ${1}\n" >&2; }

MODE="mount"
while getopts uh opt; do case "${opt}" in
  u) MODE="umount";;
  *) usage;;
esac; done
shift $(expr ${OPTIND} - 1)

if [ "${MODE}" = "mount" ]; then
  [ -n "${1}" -a -n "${2}" ] || usage
  [ "$(id -un)" = "root" ] || error "this script should be run as root" 1

  #Check image file
  [ -e "${1}" ] || error "'${1}', no such file" 1
  if ! file "${1}" | grep -q "DOS/MBR boot sector"; then
    file "${1}" | egrep -q "(archive|compressed)" && TIP="\nTip : you need to uncompress image first (eg: unzip, tar...)"
    error "'${1}' seems not to be a valid image...${TIP}" 1
  fi
  IMAGE_FILE="$(realpath "${1}")"

  #Check mountpoint
  [ -d "${2}" ] || error "'${2}', directory does not exist" 1
  MOUNTPOINT="$(realpath "${2}")"

  #Check if image is already set up on a loop device
  LOOPDEV="$(losetup -a | egrep "\(${IMAGE_FILE}\)" | sed -n 's/:.*//p')"
  if [ -n "${LOOPDEV}" ]; then
    warning "'${IMAGE_FILE}' is already set up on '${LOOPDEV}'"
  else
    LOOPDEV="$(losetup -f)"
    [ -n "${LOOPDEV}" ] || error "can't get a free loop device" 2
    losetup "${LOOPDEV}" "${IMAGE_FILE}" || error "failed to setup loop device with '${IMAGE_FILE}'" 3
  fi
  kpartx -a "${LOOPDEV}" || error "kpartx failed to add mappings for '${LOOPDEV}'" 4

  ROOTPART="$(basename "${LOOPDEV}")p2"
  ROOTMNTP="$(mount | sed -n "s/\/dev\/mapper\/${ROOTPART} on \(.\+\) type .*/\1/p")"
  [ -n "${ROOTMNTP}" ] && warning "root partition is already mounted on '${ROOTMNTP}'"
  if [ "${ROOTMNTP}" != "${MOUNTPOINT}" ]; then
    mount "/dev/mapper/${ROOTPART}" "${MOUNTPOINT}" || error "failed to mount '/dev/mapper/${ROOTPART}' on '${MOUNTPOINT}'" 5
  fi

  BOOTPART="$(basename "${LOOPDEV}")p1"
  BOOTMNTP="$(mount | sed -n "s/\/dev\/mapper\/${BOOTPART} on \(.\+\) type .*/\1/p")"
  [ -n "${BOOTMNTP}" ] && warning "boot partition is already mounted on '${BOOTMNTP}'"
  if [ "${BOOTMNTP}" != "${MOUNTPOINT}/boot" ]; then
    mount "/dev/mapper/${BOOTPART}" "${MOUNTPOINT}/boot" || error "failed to mount '/dev/mapper/${BOOTPART}' on '${MOUNTPOINT}/boot'" 5
  fi
else
  [ -n "${1}" ] || usage
  [ "$(id -un)" = "root" ] || error "this script should be run as root" 1
  [ -d "${1}" ] || error "'${1}', no such directory" 1
  mountpoint -q "${1}" || error "'${1}' seems not to be a mountpoint" 1
  MOUNTPOINT="$(echo "${1}" | sed 's/\/$//')"
  LOOPDEV="/dev/$(mount | sed -n "s@^/dev\(/.\+\)\?/\(loop[0-9]\+\)p[0-9]\+ on ${MOUNTPOINT} .*@\2@p")"
  if mountpoint -q "${MOUNTPOINT}/boot"; then
    umount "${MOUNTPOINT}/boot" || error "failed to umount '${MOUNTPOINT}/boot'" 2
  else warning "'${MOUNTPOINT}/boot' is not mounted"; fi
  umount "${MOUNTPOINT}" || error "failed to umount '${MOUNTPOINT}'" 2
  kpartx -d "${LOOPDEV}" || error "failed to remove device mappings for '${LOOPDEV}'" 2
  losetup -d "${LOOPDEV}" || error "failed to free loop device '${LOOPDEV}'" 2
fi
