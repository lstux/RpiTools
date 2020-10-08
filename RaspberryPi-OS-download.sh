#!/bin/sh

HTML_LINK="https://www.raspberrypi.org/downloads/raspberry-pi-os/"
ZIP_LINK="https://downloads.raspberrypi.org/raspios\${IMG_TYPE}_armhf_latest"

usage() {
  exec >&2
  printf "Usage : $(basename "${0}") [options] {[lite]|desktop|full}\n"
  printf "  Download latest RaspberryPI OS image (using curl)\n"
  printf "  See ${HTML_LINK}\n"
  printf "options :\n"
  printf "  -d dir : download to specified directroy instead of current directory\n"
  printf "  -l     : display download link only, don't download\n"
  printf "  -h     : display this help message\n"
  exit 1
}

DOWNLOAD_DIR="$(pwd)"
LINK_ONLY=false
IMG_TYPE="_lite"

while getopts d:lh opt; do case "${opt}" in
  d) DOWNLOAD_DIR="${OPTARG}";;
  l) LINK_ONLY=true;;
  *) usage;;
esac; done
shift $(expr ${OPTIND} - 1)
if [ -n "${1}" ]; then
  case "${1}" in
    lite|full) IMG_TYPE="_${1}";;
    desktop)   IMG_TYPE="";;
    *) printf "Error : unsupported image type '${1}'\n" >&2; usage;;
  esac
fi

if ! ${LINK_ONLY} && ! [ -d "${DOWNLOAD_DIR}" ]; then
  while true; do
    printf "Specified download directory '${DOWNLOAD_DIR}' does not exist\n" >&2
    read -p "Create download directory ? ([y]/n) " a
    case "${a}" in
      ''|y|Y) install -d "${DOWNLOAD_DIR}" || exit 2; break;;
      n|N)    exit 255;;
      *)      printf "Please answer with 'y' or 'n'...\n" >&2; sleep 2; printf "\n" >&2;;
    esac
  done
fi

eval ZIP_LINK=\"${ZIP_LINK}\"
DOWNLOAD_LINK="$(curl --head -L -s "${ZIP_LINK}" | sed -n 's/^location: \(.*\.zip\).*/\1/ip')"

[ -n "${DOWNLOAD_LINK}" ] || { printf "Error : can't get download link from '${ZIP_LINK}'...\n" >&2; exit 3; }
if ${LINK_ONLY}; then
  printf "${DOWNLOAD_LINK}\n"
  exit 0
fi

printf "Downloading from '${DOWNLOAD_LINK}'...\n" >&2
curl -o "${DOWNLOAD_DIR}/$(basename "${DOWNLOAD_LINK}")" "${DOWNLOAD_LINK}"
