#!/bin/sh
WORKDIR="$(realpath "$(dirname "${0}")")"
BUILDDIR="${WORKDIR}/build"

QEMU_GITREPO="https://git.qemu.org/git/qemu.git"
QEMU_ARCHLINK="https://download.qemu.org/qemu-\${QEMU_VERSION}.tar.xz"

QEMU_TARGETS="aarch64_be aarch64 armeb arm"
QEMU_TARGETS_AVAILABLE="aarch64_be aarch64 alpha armeb arm cris hppa i386 m68k microblazeel microblaze mips64el mips64 mipsel mips mipsn32el mipsn32 nios2 orlk ppc64ebi32 ppc64le"
QEMU_TARGETS_AVAILABLE="${QEMU_TARGETS_AVAILABLE} ppc64 ppc riscv32 riscv64 s390x sh4eb sh4 sparc32plus sparc64 sparc tilegx x86_64 xtensaeb xtensa"

# Warning : some packages must have static libraries installed for a static build.
# On gentoo, you should add the following lines in /etc/portage/package.use/qemu-static and run emerge -DuNav world :
#   app-arch/bzip2          static-libs
#   app-arch/zstd           static-libs
#   dev-libs/glib           static-libs
#   dev-libs/libpcre        static-libs
#   dev-libs/openssl        static-libs
#   net-libs/nghttp2        static-libs
#   net-misc/curl           static-libs
#   sys-libs/libcap-ng      static-libs
#   sys-libs/ncurses        static-libs
#   sys-libs/zlib           static-libs


usage() {
  exec >&2
  printf "Usage : $(basename "${0}") [options] version\n"
  printf "  Build static Qemu, version is a version number (eg: 5.1.0) or 'git'\n"
  printf "options :\n"
  printf "  -t targets : qemu linux-user targets\n"
  printf "  -l         : list available/enabled targets\n"
  printf "  -h         : display this help message\n"
  exit 1
}

targets_list() {
  local t e
  printf "Available Qemu linux-user targets :\n"
  for t in ${QEMU_TARGETS_AVAILABLE}; do
    echo " ${QEMU_TARGETS} " | egrep -q " ${t} " && e=">" || e=" "
    printf " ${e}${t}\n"
  done
  exit 0
}

targets_check() {
  local t e=0
  for t in ${QEMU_TARGETS}; do
    echo " ${QEMU_TARGETS_AVAILABLE} " | egrep -q " ${t} " && continue
    e=1; printf "Error : unsupported target '${t}', use $(basename "${0}") -l to get a list of supported targets\n" >&2
  done
  [ ${e} -ne 0 ] && exit 1
}

while getopts t:lh opt; do case "${opt}" in
  t) QEMU_TARGETS="${OPTARG}";;
  l) targets_list;;
  *) usage;;
esac; done
shift $(expr ${OPTIND} - 1)
[ -n "${1}" ] || usage
QEMU_VERSION="${1}"
targets_check

#Clone Qemu sources repository
[ -d "${BUILDDIR}" ] || install -d "${BUILDDIR}" || exit 2

if [ "${QEMU_VERSION}" = "git" ]; then
  QEMU_SRCDIR="${BUILDDIR}/$(basename "${QEMU_GITREPO}" .git)"
  if [ -d "${QEMU_SRCDIR}" ]; then
    cd "${QEMU_SRCDIR}" && \
    git pull && \
    git submodule update --recursive || exit 3
  else
    cd "${BUILDDIR}" && \
    git clone "${QEMU_GITREPO}" && \
    cd "${QEMU_SRCDIR}" && \
    git submodule init && \
    git submodule update --recursive || exit 3
  fi
else
  eval QEMU_ARCHLINK="${QEMU_ARCHLINK}"
  QEMU_LOCALARCH="${BUILDDIR}/$(basename "${QEMU_ARCHLINK}")"
  QEMU_SRCDIR="${BUILDDIR}/$(basename "${QEMU_ARCHLINK}" .tar.xz)"
  if ! [ -e "${QEMU_LOCALARCH}" ]; then
    printf "Downloading '${QEMU_ARCHLINK}'\n"
    curl -o "${QEMU_LOCALARCH}" "${QEMU_ARCHLINK}" || exit 3
  fi
  if ! [ -d "${QEMU_SRCDIR}" ]; then
    printf "Extracting ${QEMU_LOCALARCH}\n"
    cd "${BUILDDIR}" && tar xJf "${QEMU_LOCALARCH}" || exit 3
  fi
fi

#Configure Qemu sources
CONFIG_OPTS="--prefix=${BUILDDIR}/qemu-static --static --target-list=\"$(for t in ${QEMU_TARGETS}; do printf "${t}-linux-user "; done)\""
printf "Configure Qemu sources with ${CONFIG_OPTS}\n"
cd "${QEMU_SRCDIR}" && eval ./configure ${CONFIG_OPTS} || exit 4

#Build Qemu static
NB_PROCS="$(egrep "^processor\s" /proc/cpuinfo | wc -l)"
MAKEOPTS="-j$(expr ${NB_PROCS} + 1)"
make -C "${QEMU_SRCDIR}" ${MAKEOPTS} || exit 5

#Rename and get static binaries
make -C "${QEMU_SRCDIR}" install || exit 6
for b in "${BUILDDIR}/qemu-static/bin/"*; do install -v -m755 "${b}" "${BUILDDIR}/$(basename "${b}")-static"; done && rm -rf "${BUILDDIR}/qemu-static"

#Cleanup sources directory
rm -rf "${QEMU_SRCDIR}" "${QEMU_LOCALARCH}"
