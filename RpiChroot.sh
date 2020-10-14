#!/bin/sh

QEMU_SBIN=""
CHROOT_SHELL="/bin/sh"
DOMOUNTS="true"
KEEPMOUNTS="false"
VERBOSE=0

usage() {
  exec >&2
  printf "Usage : $(basename "${0}") [options] dir\n"
  printf "  chroot to specified directory, containing a Rpi fs tree\n"
  printf "options :\n"
  printf "  -q qemu-sbin : path to Qemu static binary to use as interpreter in chroot\n"
  printf "  -s shell     : use specified shell instead of default [${CHROOT_SHELL}]\n"
  printf "  -n           : don't try to mount pseudo filesystems (proc/sys...)\n"
  printf "  -k           : keep pseudo filesystems mounted on exit\n"
  printf "  -v           : increase verbosity level\n"
  printf "  -h           : display this help message\n"
  exit 1
}

error()   { printf "Error : ${1}\n" >&2; [ ${2} -ge 0 ] 2>/dev/null && exit ${2}; exit 255; }
warning() { printf "Warning : ${1}\n" >&2; }
debug()   { [ ${VERBOSE} -gt 0 ] || return 0; printf "Debug: ${1}\n" >&2; }

pseudofs_mount() {
  local rootdir="${1}" e=0
  if mountpoint -q "${rootdir}/proc"; then warning "'${rootdir}/proc' is already mounted"
  else mount -t proc proc "${rootdir}/proc" && debug "mounted procfs on '${rootdir}/proc'" || e=$(expr ${e} + 1); fi
  if mountpoint -q "${rootdir}/sys"; then warning "'${rootdir}/proc' is already mounted"
  else mount -t sysfs sys "${rootdir}/sys" && debug "mounted sysfs on '${rootdir}/sys'" || e=$(expr ${e} + 2); fi
  if mountpoint -q "${rootdir}/dev"; then warning "'${rootdir}/dev' is already mounted"
  else mount -o bind /dev "${rootdir}/dev" && debug "mounted bind /dev on '${rootdir}/dev'" || e=$(expr ${e} + 4); fi
  return ${e}
}

pseudofs_umount() {
  local rootdir="${1}" d i=1 e=0
  for d in dev sys proc; do
    if ! mountpoint -q "${rootdir}/${d}"; then warning "'${rootdir}/${d}' is not mounted"
    else umount "${rootdir}/${d}" && debug "unmounted '${rootdir}/${d}'" || e=$(expr ${e} + ${i}); fi
    i=$(expr ${i} \* 2)
  done
  return ${e}
}

qemu_prepare() {
  local rootdir="${1}" qemubin="${2}"
  local qemudst="/sbin/qemu-static"
  if [ -e "${rootdir}/${qemudst}" ]; then
    if ! diff "${qemubin}" "${rootdir}/${qemudst}"; then
      error "'${rootdir}/${qemudst}' already exists and is different from '${qemubin}'..." 2
    else debug "'${qemubin}' already copied to '${rootdir}/${qemudst}'"; fi
  else
    cp "${qemubin}" "${rootdir}/${qemudst}" || error "failed to copy '${qemubin}' to '${rootdir}/${qemudst}'" 2
  fi
  if ! [ -e /proc/sys/fs/binfmt_misc/qemu-static ]; then
    printf '%s\n' ":qemu-static:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:${qemudst}:OC" >/proc/sys/fs/binfmt_misc/register \
      || error "failed to register qemu-static in binfmt_misc" 2
  fi
  mv "${rootdir}/etc/ld.so.preload" "${rootdir}/etc/ld.so.preload.qemu_bkp" || error "failed to rename ${rootdir}/etc/ld.so.preload" 2
}

qemu_unprepare() {
  local rootdir="${1}"
  [ -e "${rootdir}/etc/ld.so.preload.qemu_bkp" ] || return 0
  mv "${rootdir}/etc/ld.so.preload.qemu_bkp" "${rootdir}/etc/ld.so.preload"
}

cleanup() {
  qemu_unprepare "${ROOTDIR}"
  ${KEEPMOUNTS} || pseudofs_umount "${ROOTDIR}"
}

while getopts q:s:nkvh opt; do case "${opt}" in
  q) [ -e "${OPTARG}" ] || error "'${OPTARG}', no such file" 1
     file "${OPTARG}" | grep -q "static" || warning "'${OPTARG}' should be a statically linked binary..."
     QEMU_SBIN="${OPTARG}";;
  s) CHROOT_SHELL="${OPTARG}";;
  n) DOMOUNTS="false";;
  k) KEEPMOUNTS="true";;
  v) VERBOSE="$(expr ${VERBOSE} + 1)";;
  *) usage;;
esac; done
shift $(expr ${OPTIND} - 1)
[ -n "${1}" ] || usage
[ -d "${1}" ] || error "'${1}' no such directory" 1
ROOTDIR="$(echo "${1}" | sed 's/\/$//')"

trap cleanup EXIT
if ${DOMOUNTS}; then pseudofs_mount "${ROOTDIR}" || exit 2; fi
if [ -e "${QEMU_SBIN}" ]; then qemu_prepare "${ROOTDIR}" "${QEMU_SBIN}" || exit 3; fi
chroot "${ROOTDIR}" "${CHROOT_SHELL}"
