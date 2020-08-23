#!/usr/bin/env bash
#shellcheck shell=bash

# Define appname (for logging)
APPNAME="deploy-rtl-sdr"

# Override branch
BRANCH_RTLSDR="d794155ba65796a76cd0a436f9709f4601509320"

# Define transient packages, required only during build
TRANS_PACKAGES=()
TRANS_PACKAGES+=('build-essential')
TRANS_PACKAGES+=('ca-certificates')
TRANS_PACKAGES+=('cmake')
TRANS_PACKAGES+=('git')
TRANS_PACKAGES+=('libusb-1.0-0-dev')
TRANS_PACKAGES+=('pkg-config')

# Define permanent packages, required for operation
PERMA_PACKAGES=()
PERMA_PACKAGES+=('libusb-1.0-0')

# Define loggiing fuction
LIGHTBLUE='\033[1;34m'
NOCOLOR='\033[0m'
function logger() {
    echo -e "${LIGHTBLUE}[$APPNAME] $1${NOCOLOR}"
}

# ===== Main Script =====

logger "deployment started"

# Do we need to run apt-get update?
if [[ -d /var/lib/apt/lists ]]; then
  APT_LISTS_PATH=(/var/lib/apt/lists/*)
  if [[ "${#APT_LISTS_PATH[@]}" -le 1 ]]; then
    logger "apt-get update required"
    apt-get update
  fi
fi

# Determine which packages need installing
PKGS_TO_INSTALL=()
PKGS_TO_REMOVE=()
for PKG in "${TRANS_PACKAGES[@]}"; do
  if dpkg -s "$PKG" > /dev/null 2>&1; then
    if dpkg-query -W --showformat='${Status}\n' "$PKG" | grep "install ok installed" > /dev/null 2>&1; then
      logger "package '$PKG' already exists"
    else
      logger "package '$PKG' will be temporarily installed"
      PKGS_TO_INSTALL+=("$PKG")
      PKGS_TO_REMOVE+=("$PKG")
    fi
  else
    logger "package '$PKG' will be temporarily installed"
    PKGS_TO_INSTALL+=("$PKG")
    PKGS_TO_REMOVE+=("$PKG")
  fi
done
for PKG in "${PERMA_PACKAGES[@]}"; do
  if dpkg -s "$PKG" > /dev/null 2>&1; then
    if dpkg-query -W --showformat='${Status}\n' "$PKG" | grep "install ok installed" > /dev/null 2>&1; then
      logger "package '$PKG' already exists"
    else
      logger "package '$PKG' will be installed"
      PKGS_TO_INSTALL+=("$PKG")
    fi
  else
    logger "package '$PKG' will be installed"
    PKGS_TO_INSTALL+=("$PKG")
  fi
done

# Install packages
logger "installing packages"
apt-get install --no-install-recommends -y "${PKGS_TO_INSTALL[@]}"

# Clone RTL-SDR repo
logger "cloning RTL-SDR repo"
git clone git://git.osmocom.org/rtl-sdr.git /src/rtl-sdr
pushd /src/rtl-sdr || exit 1

# If BRANCH_RTLSDR is not already set, use the latest branch
if [[ -z "$BRANCH_RTLSDR" ]]; then
    BRANCH_RTLSDR="$(git tag --sort='-creatordate' | head -1)"
    logger "BRANCH_RTLSDR not set, will build branch/tag '$BRANCH_RTLSDR'"
else
    logger "will build branch/tag '$BRANCH_RTLSDR'"
fi

# Check out requested version
git checkout "${BRANCH_RTLSDR}"
echo "rtl-sdr ${BRANCH_RTLSDR}" >> /VERSIONS

# Build
logger "building rtl-sdr"
mkdir -p /src/rtl-sdr/build
pushd /src/rtl-sdr/build || exit 1
cmake ../ -DINSTALL_UDEV_RULES=ON -Wno-dev ##
make -Wstringop-truncation
make -Wstringop-truncation install
cp -v /src/rtl-sdr/rtl-sdr.rules /etc/udev/rules.d/
ldconfig
popd || exit 1
popd || exit 1

# Test
# logger "Testing rtl-sdr"

# Clean up
logger "Cleaning up"
apt-get remove -y "${PKGS_TO_REMOVE[@]}"
apt-get autoremove -y
rm -rf /src/rtl-sdr

logger "Finished"
